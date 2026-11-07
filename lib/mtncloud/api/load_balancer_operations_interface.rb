require 'mtncloud/api/api_client'
require 'securerandom'
require 'digest'

# Runs load balancer operations.
#
# MTN Cloud's load balancers are managed by a console plugin reached through one public task,
# not through a REST endpoint. Each operation executes that task with an action and its inputs,
# then reads the plugin's answer from the job execution:
#
#   POST /api/tasks/{task id}/execute   {"job": {"targetType": "appliance", "customOptions": {"action": ..., inputs}}}
#   GET  /api/job-executions/{id}       until it ends, then the output of its executeTask event
#
# The plugin acts as the logged-in user and enforces tenancy itself, so no tenant, account or user
# is ever sent. The task's id differs between tenants, so it is found by its code.
#
#   ops = api_client.load_balancer_operations
#   answer = ops.run('list', {'networkId' => 114})
#   answer['result']['loadbalancers']
#
# run returns the plugin's whole answer: result, pending, piece, warning, alreadyGone, steps...
# A refusal or a failure raises MtnCloud::Cli::LoadBalancerError. In dry run mode nothing is sent,
# not even the task lookup, and run returns the execute request.
class MtnCloud::LoadBalancerOperationsInterface < MtnCloud::APIClient

  # The code of the public task that runs load balancer operations.
  TASK_CODE = 'lboperate.terraform'

  # Actions that change nothing: running one again is always safe.
  READ_ACTIONS = %w[whoami list read fip-options]
  # Writes that are safe to repeat after a run with no answer: a create carries a requestId, so the
  # plugin answers a repeat with the piece already made (existing: true); a delete of something
  # already gone answers alreadyGone; attaching what is attached, or detaching what is not, changes
  # nothing. Every other write (the updates) may have acted, and is never repeated.
  REPEATABLE_WRITES = %w[create listener-create pool-create member-add monitor-create l7policy-create
                         fip-attach fip-detach
                         delete listener-delete pool-delete member-remove monitor-delete l7policy-delete]

  # Job execution statuses that mean it has not ended yet.
  RUNNING_STATUSES = %w[new queued pending running]
  # The status run_once reports for an attempt that ran out of time while its job may still run.
  TIMED_OUT = 'timed out'
  # The statuses run_once reports when the execute request failed: it never reached the console
  # (nothing ran), or it may have reached it and the reply was lost (a job may be running).
  NOT_DELIVERED = 'not delivered'
  NO_REPLY = 'no reply'

  # Retries of a run that did nothing, and the wait before each. Each retry is a new job execution.
  RETRY_WAITS = [5, 10, 20, 40]
  # Job execution reads in a row that may answer 404 while a new execution appears.
  MAX_MISSING_JOB = 10
  # Polling backoff, in seconds.
  POLL_FIRST = 0.5
  POLL_MAX = 15

  # Time limits, in seconds: one attempt, and the whole operation with its retries. A write waits
  # longer: the plugin itself waits up to 3 minutes for the load balancer to settle.
  DEFAULT_TIME_LIMITS = {read_attempt: 120, read_total: 300, write_attempt: 420, write_total: 900}

  # Task ids found by code, per remote and identity. The key is the remote's URL and a digest of
  # the access token, so one login never reuses an id found by another, and no token is held here.
  @task_ids = {}
  class << self
    attr_reader :task_ids
  end

  attr_writer :sleeper, :clock, :time_limits

  # A new requestId for one create. Give the same one to every retry of that create.
  def self.new_request_id
    "cli" + SecureRandom.hex(16)
  end

  def run(action, inputs={})
    action = action.to_s
    custom_options = custom_options(action, inputs)
    if @dry_run
      return execute(method: :post, url: "/api/tasks/{#{TASK_CODE}}/execute", payload: job_payload(action, custom_options))
    end
    write = !READ_ACTIONS.include?(action)
    deadline = now + time_limit(write ? :write_total : :read_total)
    attempt = 0
    loop do
      status, envelope, job_id = run_once(action, custom_options, write, deadline)
      if retry?(action, status, envelope) && attempt < RETRY_WAITS.size && now + RETRY_WAITS[attempt] < deadline
        log("load balancer #{action} did nothing (#{retry_reason(status, envelope)}), retrying, attempt #{attempt + 2}")
        sleep_for(RETRY_WAITS[attempt])
        attempt += 1
        next
      end
      return answer(action, status, envelope, job_id, write)
    end
  end

  # Rewrites the cloud software's names in a message from the plugin, so customers read MTN Cloud
  # terms. Longer and more specific names go first.
  def self.customer_text(msg)
    msg.to_s
      .sub(/\Aopenstack /i, "The cloud ") # mtncloud:allow-cloud-name (rewrites the cloud software name)
      .gsub(/\b(the) openstack\b/i) { "#{$1} cloud" } # mtncloud:allow-cloud-name (rewrites the cloud software name)
      .gsub(/openstack/i, "the cloud") # mtncloud:allow-cloud-name (rewrites the cloud software name)
      .gsub(/octavia/i, "the load balancer service") # mtncloud:allow-cloud-name (rewrites the load balancer service name)
      .gsub(/keystone/i, "the cloud's sign-in") # mtncloud:allow-cloud-name (rewrites the identity service name)
      .gsub(/barbican/i, "the certificate store") # mtncloud:allow-cloud-name (rewrites the certificate service name)
      .gsub(/neutron/i, "the network service") # mtncloud:allow-cloud-name (rewrites the network service name)
      .gsub(/amphorae/i, "load balancer VMs") # mtncloud:allow-cloud-name (rewrites the load balancer VM name)
      .gsub(/amphora/i, "load balancer VM") # mtncloud:allow-cloud-name (rewrites the load balancer VM name)
  end

  protected

  # Every input goes inside job.customOptions, as strings; spec stays a JSON object.
  # Inputs that are nil are left out.
  def custom_options(action, inputs)
    opts = {"action" => action}
    (inputs || {}).each do |k, v|
      next if v.nil?
      opts[k.to_s] = (k.to_s == "spec" || v.is_a?(Hash) || v.is_a?(Array)) ? v : v.to_s
    end
    opts
  end

  def job_payload(action, custom_options)
    {"job" => {"name" => "mtncloud-lb-#{action}-#{SecureRandom.hex(4)}", "targetType" => "appliance",
               "customOptions" => custom_options}}
  end

  # Executes the task once and waits for its job execution to end.
  # Returns [job status, plugin answer or nil when the job left none, job execution id].
  def run_once(action, custom_options, write, deadline)
    limit_at = [now + time_limit(write ? :write_attempt : :read_attempt), deadline].min
    job_id = start_job(action, custom_options)
    return [job_id, nil, nil] if job_id == NOT_DELIVERED || job_id == NO_REPLY
    job = poll_job(action, job_id, limit_at)
    return [TIMED_OUT, nil, job_id] if job.nil?
    [job["status"].to_s, envelope_of(job), job_id]
  end

  # POST execute. Returns the job execution id, NOT_DELIVERED when the request never reached the
  # console (no connection was made), or NO_REPLY when it may have reached it but no reply came
  # (a job may have started).
  def start_job(action, custom_options, rediscovered=false)
    task_id, cached = task_id_for_identity
    begin
      started = execute(method: :post, url: "/api/tasks/#{task_id}/execute", payload: job_payload(action, custom_options))
    rescue RestClient::Forbidden, RestClient::NotFound => e
      forget_task_id
      # a task id remembered from earlier may be stale: look it up once more
      return start_job(action, custom_options, true) if cached && !rediscovered
      raise access_error(action, {http_status: e.http_code, response: response_text(e)})
    rescue RestClient::Unauthorized
      raise
    rescue RestClient::Exceptions::OpenTimeout, Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError => e
      # no connection was made, so nothing reached the console
      log("load balancer #{action}: the console could not be reached, nothing was sent (#{e.message})")
      return NOT_DELIVERED
    rescue RestClient::Exception => e
      raise unless e.http_code.to_i >= 500 || e.is_a?(RestClient::Exceptions::Timeout) || e.is_a?(RestClient::ServerBrokeConnection)
      log("load balancer #{action}: the console did not reply to the execute request (#{e.message})")
      return NO_REPLY
    rescue Errno::ECONNRESET, Errno::EPIPE, Errno::ETIMEDOUT, IOError => e
      log("load balancer #{action}: the connection to the console failed after the request was sent (#{e.message})")
      return NO_REPLY
    end
    id = started.is_a?(Hash) && started["jobExecution"].is_a?(Hash) ? started["jobExecution"]["id"] : nil
    if id.nil?
      raise MtnCloud::Cli::LoadBalancerError.new("The console accepted the load balancer #{action} operation but did not say which job runs it.",
        kind: :unexpected, action: action, details: {response: started})
    end
    id
  end

  # Reads the job execution until it ends. nil when time ran out first.
  def poll_job(action, job_id, limit_at)
    wait = POLL_FIRST
    missing = 0
    loop do
      remaining = limit_at - now
      return nil if remaining <= 0
      sleep_for([wait, remaining].min)
      wait = [wait * 2, POLL_MAX].min
      begin
        response = execute(method: :get, url: "/api/job-executions/#{job_id}")
      rescue RestClient::NotFound => e
        # a new execution can take a moment to appear, but not forever. The task may still have run.
        missing += 1
        if missing >= MAX_MISSING_JOB
          raise MtnCloud::Cli::LoadBalancerError.new(
            "The load balancer #{action} operation started (job execution #{job_id}), but its job execution " \
            "could not be read: not found #{missing} times in a row. It may still have run. " \
            "Check the load balancer before trying again.",
            kind: :job_not_found, action: action,
            details: {job_execution_id: job_id, not_found_reads: missing, http_status: e.http_code, response: response_text(e)})
        end
        next
      rescue RestClient::Unauthorized
        raise
      rescue RestClient::Exception => e
        # reading a job execution is safe to repeat while time remains
        raise unless e.http_code.to_i >= 500 || e.is_a?(RestClient::Exceptions::Timeout) || e.is_a?(RestClient::ServerBrokeConnection)
        next
      rescue Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT, SocketError, IOError
        next
      end
      missing = 0
      job = response.is_a?(Hash) ? response["jobExecution"] : nil
      next unless job.is_a?(Hash)
      return job unless RUNNING_STATUSES.include?(job["status"].to_s)
    end
  end

  # The plugin's answer: the output of the executeTask event. Output that isn't a JSON object
  # (a stack trace, say) counts as no answer.
  def envelope_of(job)
    events = (job["process"].is_a?(Hash) ? job["process"]["events"] : nil) || []
    events.each do |event|
      next unless event.is_a?(Hash) && event["processType"].is_a?(Hash) && event["processType"]["code"] == "executeTask"
      output = event["output"].to_s
      next if output.strip.empty?
      begin
        parsed = JSON.parse(output)
        return parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
        next
      end
    end
    nil
  end

  # A run that did nothing and can be tried again: the console stalled before the plugin read its
  # inputs (action is null), or the plugin said so itself (retryable, or a failed lookup).
  # A run without an answer depends on what is known about it:
  # - the execute request never reached the console: nothing ran, so any action is tried again;
  # - it may have reached it, or the attempt ran out of time while its job may still run: only a
  #   read is tried again. A write is never executed a second time while the first may be running;
  # - the job ended without an answer: it may have acted, but it has finished, so reads and the
  #   repeatable writes are tried again.
  # A refusal is never retried.
  def retry?(action, status, envelope)
    if envelope.nil?
      case status
      when NOT_DELIVERED then return true
      when NO_REPLY, TIMED_OUT then return READ_ACTIONS.include?(action)
      when "error" then return repeatable?(action)
      else return false
      end
    end
    return false if envelope["success"] == true
    return true if input_timeout?(envelope)
    result = envelope["result"].is_a?(Hash) ? envelope["result"] : {}
    envelope["retryable"] == true || result["retryable"] == true || result["lookupFailed"] == true
  end

  def input_timeout?(envelope)
    envelope["action"].to_s.empty? && envelope["error"].to_s.include?("did not signal an event")
  end

  def retry_reason(status, envelope)
    return "the request never reached the console" if envelope.nil? && status == NOT_DELIVERED
    return "no reply from the console" if envelope.nil? && status == NO_REPLY
    return "no answer, job #{status}" if envelope.nil?
    return "the console stalled before the operation started" if input_timeout?(envelope)
    "the load balancer service asked for a retry"
  end

  def repeatable?(action)
    READ_ACTIONS.include?(action) || REPEATABLE_WRITES.include?(action)
  end

  # The answer, or the error for a run that failed.
  def answer(action, status, envelope, job_id, write)
    if envelope.nil?
      may_have_acted = write ? " It may have been applied: check the load balancer before trying again." : " Try again."
      if status == TIMED_OUT
        raise MtnCloud::Cli::LoadBalancerError.new(
          "The load balancer #{action} operation did not finish in time (job execution #{job_id}).#{may_have_acted}",
          kind: :timed_out, action: action, details: {job_execution_id: job_id, job_status: status})
      end
      if status == NOT_DELIVERED
        raise MtnCloud::Cli::LoadBalancerError.new(
          "The load balancer #{action} operation could not reach the console, so nothing was sent. Try again.",
          kind: :no_answer, action: action, details: {delivery: status})
      end
      if status == NO_REPLY
        raise MtnCloud::Cli::LoadBalancerError.new(
          "The console did not reply to the load balancer #{action} request.#{may_have_acted}",
          kind: :no_answer, action: action, details: {delivery: status})
      end
      raise MtnCloud::Cli::LoadBalancerError.new(
        "The load balancer #{action} operation ended (#{status}) without an answer#{job_id ? " (job execution #{job_id})" : ""}.#{may_have_acted}",
        kind: :no_answer, action: action, details: {job_execution_id: job_id, job_status: status})
    end
    if envelope["success"] != true
      piece = envelope["piece"].is_a?(Hash) ? envelope["piece"]["id"] : nil
      raise MtnCloud::Cli::LoadBalancerError.new(failure_text(action, envelope),
        kind: :refused, action: action, rolled_back: rolled_back?(envelope), left_behind: left_behind(envelope),
        piece_id: (REPEATABLE_WRITES.include?(action) ? piece : nil),
        details: {job_execution_id: job_id, job_status: status, error: envelope["error"], retryable: envelope["retryable"]})
    end
    result = envelope["result"]
    if (result.nil? || (result.respond_to?(:empty?) && result.empty?)) && envelope["alreadyGone"] != true
      raise MtnCloud::Cli::LoadBalancerError.new("The load balancer #{action} operation answered without a result. Try again.",
        kind: :unexpected, action: action, details: {job_execution_id: job_id, job_status: status})
    end
    envelope
  end

  # A refused save's message, with what it took back and what it left behind.
  def failure_text(action, envelope)
    msg = envelope["error"].to_s.strip
    msg = "The load balancer #{action} operation failed without a message." if msg.empty?
    msg = self.class.customer_text(msg)
    rolled_back = rolled_back?(envelope)
    left = left_behind(envelope)
    msg += "." if (rolled_back || left.any?) && !msg.end_with?(".")
    if rolled_back && left.empty?
      msg += " What this change created was removed again, so you can try again from a clean state."
    end
    if left.any?
      parts = left.collect do |p|
        s = "#{p['kind']} \"#{p['name']}\" (#{p['id']})"
        s += ", kept" if p['kept']
        s += ": #{self.class.customer_text(p['error'])}" if p['error'].to_s != ""
        s
      end
      msg += " Left on the load balancer: #{parts.join('; ')}. Check the load balancer before trying again."
    end
    msg
  end

  # rolledBack at the top of the answer, in its result, or on one of its steps.
  def rolled_back?(envelope)
    return true if envelope["rolledBack"] == true
    result = envelope["result"].is_a?(Hash) ? envelope["result"] : {}
    return true if result["rolledBack"] == true
    steps = Array(envelope["steps"]) + Array(result["steps"])
    steps.any? {|s| s.is_a?(Hash) && s["rolledBack"] == true }
  end

  # leftBehind at the top of the answer, or in its result.
  def left_behind(envelope)
    result = envelope["result"].is_a?(Hash) ? envelope["result"] : {}
    list = envelope["leftBehind"] || result["leftBehind"]
    Array(list).select {|p| p.is_a?(Hash) }
  end

  # The task id for this remote and login, looked up by code once. Returns [id, found in the cache].
  def task_id_for_identity
    key = identity_key
    if key && self.class.task_ids[key]
      return [self.class.task_ids[key], true]
    end
    id = find_task_id
    self.class.task_ids[key] = id if key
    [id, false]
  end

  def forget_task_id
    key = identity_key
    self.class.task_ids.delete(key) if key
  end

  # The remote and a digest of the access token. nil without a token: then nothing is cached.
  def identity_key
    return nil if @access_token.to_s.empty?
    "#{@base_url}|#{Digest::SHA256.hexdigest(@access_token.to_s)}"
  end

  # Pages through /api/tasks, which ignores a code filter, and matches the code exactly.
  def find_task_id
    offset = 0
    page_size = 100
    loop do
      begin
        response = execute(method: :get, url: "/api/tasks", params: {max: page_size, offset: offset})
      rescue RestClient::Forbidden, RestClient::NotFound => e
        raise access_error(nil, {http_status: e.http_code, response: response_text(e), step: "task lookup"})
      end
      tasks = response.is_a?(Hash) && response["tasks"].is_a?(Array) ? response["tasks"] : []
      found = tasks.find {|t| t.is_a?(Hash) && t["code"] == TASK_CODE }
      return found["id"] if found
      total = response.is_a?(Hash) && response["meta"].is_a?(Hash) ? response["meta"]["total"] : nil
      offset += tasks.size
      break if tasks.empty? || (total && offset >= total.to_i)
    end
    raise access_error(nil, {step: "task lookup", searched: offset})
  end

  def access_error(action, details)
    MtnCloud::Cli::LoadBalancerError.new(
      "Your role is not allowed to run load balancer operations. Ask your administrator to grant access.",
      kind: :access, action: action, details: details)
  end

  def response_text(e)
    e.respond_to?(:response) && e.response ? e.response.to_s[0, 500] : nil
  end

  def time_limit(name)
    ((@time_limits || {})[name] || DEFAULT_TIME_LIMITS[name]).to_f
  end

  def now
    @clock ? @clock.call : Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def sleep_for(seconds)
    @sleeper ? @sleeper.call(seconds) : sleep(seconds)
  end

  def log(msg)
    MtnCloud::Logging::DarkPrinter.puts(msg) if MtnCloud::Logging.debug?
  end
end
