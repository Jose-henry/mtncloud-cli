require 'test/unit'
require 'json'
require 'stringio'
require 'mtncloud'

# Offline tests for the load balancer task client: task discovery, the execute payload, polling,
# reading the plugin's answer, retries and their bounds, and error reporting.
# A scripted console stands in for the API, and time only moves when the client waits, so the
# tests are deterministic and never sleep.
class LoadBalancerOperationsInterfaceTest < Test::Unit::TestCase

  OPS = MtnCloud::LoadBalancerOperationsInterface
  TASK = {"id" => 451, "name" => "LoadBalancer Operations", "code" => "lboperate.terraform"}

  # Serves /api/tasks pages, execute responses and job execution reads, in order, and records
  # every request. An Exception in a queue is raised instead of answered.
  class FakeConsole
    attr_reader :requests

    def initialize(task_pages: [[TASK]], executes: [], polls: [])
      @task_pages = task_pages
      @executes = executes
      @polls = polls
      @requests = []
      @next_job = 1000
    end

    def call(opts)
      @requests << opts
      url = opts[:url].to_s
      if opts[:method] == :get && url.end_with?("/api/tasks")
        offset = (opts[:params] || {})[:offset].to_i
        page_index = 0
        seen = 0
        while page_index < @task_pages.size && seen < offset
          seen += @task_pages[page_index].size
          page_index += 1
        end
        page = @task_pages[page_index] || []
        return page if page.is_a?(Exception) ? raise(page) : false
        {"tasks" => page, "meta" => {"total" => @task_pages.flatten.size}}
      elsif opts[:method] == :post && url =~ %r{/api/tasks/(\d+)/execute\z}
        item = @executes.shift
        raise item if item.is_a?(Exception)
        item || {"jobExecution" => {"id" => (@next_job += 1)}}
      elsif opts[:method] == :get && url =~ %r{/api/job-executions/(\d+)\z}
        item = @polls.shift
        raise item if item.is_a?(Exception)
        raise "no job execution read scripted" if item.nil?
        item
      else
        raise "unexpected request #{opts[:method]} #{url}"
      end
    end

    def executes
      @requests.select {|r| r[:method] == :post }
    end

    def payload(n)
      JSON.parse(executes[n][:payload].is_a?(String) ? executes[n][:payload] : executes[n][:payload].to_json)
    end

    def task_lookups
      @requests.select {|r| r[:method] == :get && r[:url].to_s.end_with?("/api/tasks") }
    end
  end

  def setup
    OPS.task_ids.clear
    @waits = []
    @time = 0.0
  end

  def ops(console, url: "https://console.example.test", token: "token-a")
    o = OPS.new(url: url, access_token: token)
    o.define_singleton_method(:execute) {|opts, options={}| console.call(opts) }
    o.sleeper = lambda {|s| @waits << s; @time += s }
    o.clock = lambda { @time }
    o
  end

  def job(status, output = :none)
    events = []
    unless output == :none
      events << {"processType" => {"code" => "executeTask"}, "status" => "complete",
                 "output" => (output.is_a?(String) ? output : output.to_json)}
    end
    events << {"processType" => {"code" => "jobComplete"}, "status" => "complete"}
    {"jobExecution" => {"id" => 1001, "status" => status, "process" => {"events" => events}}}
  end

  def ok(result = {"success" => true, "loadbalancers" => [], "total" => 0, "canManage" => true}, extra = {})
    {"success" => true, "action" => "list", "caller" => {"userId" => 7, "username" => "neo", "accountId" => 2},
     "permissionSource" => "task-access", "networkAccess" => "owner", "result" => result}.merge(extra)
  end

  def refused(msg, extra = {})
    {"success" => false, "action" => "pool-create", "error" => msg}.merge(extra)
  end

  INPUT_TIMEOUT = {"success" => false, "action" => nil,
                   "error" => "RuntimeException: java.util.concurrent.TimeoutException: The source did not signal an event for 15000 milliseconds and has been terminated."}

  def not_found
    RestClient::NotFound.new(nil, 404)
  end

  # --- task discovery ---------------------------------------------------------------

  def test_finds_the_task_by_its_exact_code_on_a_later_page
    others = [{"id" => 1, "code" => "lboperate.terraform.old"}, {"id" => 2, "code" => "LBOPERATE.TERRAFORM"}]
    console = FakeConsole.new(task_pages: [others, [TASK]], polls: [job("success", ok)])
    ops(console).run("list", {"networkId" => 114})
    assert_equal [0, 2], console.task_lookups.collect {|r| r[:params][:offset] }
    assert_match %r{/api/tasks/451/execute\z}, console.executes[0][:url]
  end

  def test_a_missing_task_is_the_access_error
    console = FakeConsole.new(task_pages: [[{"id" => 1, "code" => "something.else"}]])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("list", {"networkId" => 114}) }
    assert_equal :access, err.kind
    assert_equal "Your role is not allowed to run load balancer operations. Ask your administrator to grant you access to the Load Balancer Operations task.", err.message
    assert_empty console.executes
  end

  def test_a_refused_task_list_is_the_access_error
    console = FakeConsole.new(task_pages: [RestClient::Forbidden.new(nil, 403)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("list", {"networkId" => 114}) }
    assert_equal :access, err.kind
    assert_equal 403, err.details[:http_status]
  end

  def test_the_task_id_is_cached_per_remote_and_identity
    console = FakeConsole.new(polls: Array.new(5) { job("success", ok) })
    ops(console).run("list", {"networkId" => 114})
    ops(console).run("list", {"networkId" => 114})                                  # same remote and login
    assert_equal 1, console.task_lookups.size
    ops(console, token: "token-b").run("list", {"networkId" => 114})                # another login
    assert_equal 2, console.task_lookups.size
    ops(console, url: "https://other.example.test").run("list", {"networkId" => 114}) # another remote
    assert_equal 3, console.task_lookups.size
    # the cache never holds an access token
    OPS.task_ids.keys.each {|k| assert_no_match(/token-a|token-b/, k) }
  end

  def test_without_a_token_nothing_is_cached
    console = FakeConsole.new(polls: Array.new(2) { job("success", ok) })
    ops(console, token: nil).run("list", {"networkId" => 114})
    ops(console, token: nil).run("list", {"networkId" => 114})
    assert_equal 2, console.task_lookups.size
    assert_empty OPS.task_ids
  end

  def test_a_stale_cached_task_id_is_looked_up_once_more
    console = FakeConsole.new(polls: [job("success", ok), job("success", ok)])
    ops(console).run("list", {"networkId" => 114})
    console.instance_variable_get(:@executes).push(not_found)
    ops(console).run("list", {"networkId" => 114})
    assert_equal 2, console.task_lookups.size
    assert_equal 3, console.executes.size
  end

  def test_a_refused_execute_is_the_access_error_and_is_not_retried
    [RestClient::Forbidden.new(nil, 403), not_found].each do |refusal|
      OPS.task_ids.clear
      console = FakeConsole.new(executes: [refusal])
      err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("list", {"networkId" => 114}) }
      assert_equal :access, err.kind
      assert_equal 1, console.executes.size
    end
  end

  # --- the execute payload ------------------------------------------------------------

  def test_inputs_go_inside_custom_options_as_strings_and_spec_stays_an_object
    console = FakeConsole.new(polls: [job("success", ok({"floatingip" => {"id" => "f1"}}))])
    spec = {"name" => "web", "port" => 80, "rules" => [{"type" => "PATH"}]}
    ops(console).run("fip-detach", {"networkId" => 114, "lbId" => "lb-1", "release" => false, "spec" => spec, "skipped" => nil})
    job = console.payload(0)["job"]
    assert_equal "appliance", job["targetType"]
    assert_match(/\Amtncloud-lb-fip-detach-[0-9a-f]{8}\z/, job["name"])
    assert_equal({"action" => "fip-detach", "networkId" => "114", "lbId" => "lb-1", "release" => "false", "spec" => spec},
                 job["customOptions"])
    assert_nil console.payload(0)["customOptions"], "nothing may sit at the top level"
  end

  def test_request_ids_are_new_for_each_create
    a, b = OPS.new_request_id, OPS.new_request_id
    assert_not_equal a, b
    assert_match(/\A[A-Za-z0-9_-]{8,64}\z/, a)
  end

  # --- polling ------------------------------------------------------------------------

  def test_polls_until_the_job_ends_with_backoff
    console = FakeConsole.new(polls: [job("queued"), job("running"), job("running"), job("success", ok)])
    answer = ops(console).run("list", {"networkId" => 114})
    assert_equal true, answer["success"]
    assert_equal [0.5, 1.0, 2.0, 4.0], @waits
  end

  def test_the_backoff_is_capped
    console = FakeConsole.new(polls: Array.new(8) { job("running") } + [job("success", ok)])
    ops(console).run("list", {"networkId" => 114})
    assert_equal 15, @waits.max
  end

  def test_a_job_execution_that_appears_late_is_waited_for
    console = FakeConsole.new(polls: [not_found, not_found, job("success", ok)])
    assert_equal true, ops(console).run("list", {"networkId" => 114})["success"]
  end

  def test_a_job_execution_that_never_appears_is_not_reported_as_access
    console = FakeConsole.new(polls: Array.new(10) { not_found })
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114, "lbId" => "lb-1"}) }
    assert_equal :job_not_found, err.kind
    assert_equal 1001, err.details[:job_execution_id]
    assert_equal 10, err.details[:not_found_reads]
    assert_equal 404, err.details[:http_status]
    assert_match(/may still have run/, err.message)
    assert_no_match(/not allowed/, err.message)
    assert_equal 1, console.executes.size
  end

  def test_transient_errors_while_polling_are_ridden_out
    console = FakeConsole.new(polls: [RestClient::InternalServerError.new(nil, 500), RestClient::Exceptions::ReadTimeout.new,
                                      job("success", ok)])
    assert_equal true, ops(console).run("list", {"networkId" => 114})["success"]
  end

  def test_an_attempt_that_runs_out_of_time_is_timed_out_and_an_update_is_not_retried
    console = FakeConsole.new(polls: Array.new(200) { job("running") })
    o = ops(console)
    o.time_limits = {write_attempt: 60, write_total: 600}
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { o.run("pool-update", {"networkId" => 114, "lbId" => "lb-1"}) }
    assert_equal :timed_out, err.kind
    assert_match(/may have been applied/, err.message)
    assert_equal 1, console.executes.size
    assert_operator @time, :<=, 60
  end

  # --- reading the answer -------------------------------------------------------------

  def test_the_answer_is_returned_whole
    answer = ok({"success" => true, "piece" => nil}, {"pending" => true, "piece" => {"id" => "p1"}, "warning" => "a rule is in ERROR"})
    console = FakeConsole.new(polls: [job("success", answer)])
    got = ops(console).run("pool-update", {"networkId" => 114, "lbId" => "lb-1", "poolId" => "p1"})
    assert_equal true, got["pending"]
    assert_equal "p1", got["piece"]["id"]
    assert_equal "a rule is in ERROR", got["warning"]
  end

  def test_job_status_and_answer_are_both_checked
    # the job succeeded, but the plugin refused the operation
    console = FakeConsole.new(polls: [job("success", refused("Pool p9 is not on this load balancer."))])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal :refused, err.kind
    assert_equal "Pool p9 is not on this load balancer.", err.message
    # the job failed and left no answer
    console = FakeConsole.new(polls: [job("error")])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal :no_answer, err.kind
  end

  def test_output_that_is_not_an_answer_counts_as_no_answer
    console = FakeConsole.new(polls: [job("error", "java.lang.NullPointerException\n\tat Foo.bar")])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("listener-update", {"networkId" => 114}) }
    assert_equal :no_answer, err.kind
  end

  def test_a_success_without_a_result_is_unexpected_unless_already_gone
    console = FakeConsole.new(polls: [job("success", {"success" => true, "action" => "list"})])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("list", {"networkId" => 114}) }
    assert_equal :unexpected, err.kind
    console = FakeConsole.new(polls: [job("success", {"success" => true, "action" => "pool-delete", "alreadyGone" => true, "pending" => false})])
    assert_equal true, ops(console).run("pool-delete", {"networkId" => 114, "lbId" => "lb-1", "poolId" => "p1"})["alreadyGone"]
  end

  # --- retries ------------------------------------------------------------------------

  def test_the_input_timeout_stall_is_retried_for_every_action
    %w[read pool-create pool-update pool-delete].each do |action|
      OPS.task_ids.clear
      @waits = []
      console = FakeConsole.new(polls: [job("error", INPUT_TIMEOUT), job("success", ok)])
      assert_equal true, ops(console).run(action, {"networkId" => 114})["success"]
      assert_equal 2, console.executes.size, action
      assert_include @waits, 5, action
    end
  end

  def test_a_run_the_plugin_says_is_retryable_is_retried
    [refused("Another save of this load balancer is in progress. Try again in a moment.", "retryable" => true),
     refused("The console did not answer in time.", "result" => {"lookupFailed" => true}),
     refused("slow", "result" => {"retryable" => true})].each do |first|
      OPS.task_ids.clear
      console = FakeConsole.new(polls: [job("success", first), job("success", ok)])
      assert_equal true, ops(console).run("pool-update", {"networkId" => 114})["success"]
      assert_equal 2, console.executes.size
    end
  end

  def test_a_run_with_no_answer_is_retried_only_when_repeating_it_is_safe
    {"read" => 2, "list" => 2, "create" => 2, "pool-create" => 2, "fip-attach" => 2, "pool-delete" => 2, "delete" => 2,
     "pool-update" => 1, "loadbalancer-update" => 1, "member-update" => 1, "l7policy-update" => 1}.each do |action, executes|
      OPS.task_ids.clear
      console = FakeConsole.new(polls: [job("error"), job("success", ok)])
      o = ops(console)
      if executes == 2
        assert_equal true, o.run(action, {"networkId" => 114})["success"], action
      else
        err = assert_raise(MtnCloud::Cli::LoadBalancerError, action) { o.run(action, {"networkId" => 114}) }
        assert_equal :no_answer, err.kind
        assert_match(/may have been applied/, err.message)
      end
      assert_equal executes, console.executes.size, action
    end
  end

  def test_an_execute_that_gets_no_answer_is_retried_only_when_safe
    console = FakeConsole.new(executes: [RestClient::Exceptions::ReadTimeout.new], polls: [job("success", ok)])
    assert_equal true, ops(console).run("read", {"networkId" => 114, "lbId" => "lb-1"})["success"]
    assert_equal 2, console.executes.size
    OPS.task_ids.clear
    console = FakeConsole.new(executes: [RestClient::Exceptions::ReadTimeout.new])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal :no_answer, err.kind
    assert_equal 1, console.executes.size
  end

  def test_a_retried_create_sends_the_same_request_id
    request_id = OPS.new_request_id
    console = FakeConsole.new(polls: [job("error"), job("success", INPUT_TIMEOUT), job("success", ok({"existing" => true}))])
    ops(console).run("pool-create", {"networkId" => 114, "lbId" => "lb-1", "requestId" => request_id, "spec" => {"name" => "web"}})
    assert_equal 3, console.executes.size
    assert_equal [request_id] * 3, (0..2).collect {|n| console.payload(n)["job"]["customOptions"]["requestId"] }
  end

  def test_a_refusal_is_never_retried
    console = FakeConsole.new(polls: [job("success", refused("Listener port 80 is already used on this load balancer."))])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("listener-create", {"networkId" => 114}) }
    assert_equal :refused, err.kind
    assert_equal 1, console.executes.size
    assert_empty @waits.select {|w| w >= 5 }
  end

  def test_retries_are_bounded_in_number
    always = Array.new(10) { job("success", refused("busy", "retryable" => true)) }
    console = FakeConsole.new(polls: always)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("list", {"networkId" => 114}) }
    assert_equal :refused, err.kind
    assert_equal 5, console.executes.size
    assert_equal [5, 10, 20, 40], @waits.select {|w| w >= 5 }
  end

  def test_retries_are_bounded_in_time
    always = Array.new(10) { job("success", refused("busy", "retryable" => true)) }
    console = FakeConsole.new(polls: always)
    o = ops(console)
    o.time_limits = {read_attempt: 120, read_total: 20}
    assert_raise(MtnCloud::Cli::LoadBalancerError) { o.run("list", {"networkId" => 114}) }
    assert_operator console.executes.size, :<, 5
    assert_operator @time, :<, 20
  end

  # --- execute failures and timed-out attempts: never a second write while the first may run

  WRITES = %w[create pool-create member-add delete pool-delete fip-attach fip-detach pool-update loadbalancer-update]

  # An error as Net::HTTP raises it while opening the connection: the same class, its message
  # prefixed with "Failed to open TCP connection to host:port".
  def connect_failure(error)
    error.exception("Failed to open TCP connection to console.example.test:443 (#{error.message})")
  end

  # the request never reached the console: no connection was made
  def not_delivered_errors
    [RestClient::Exceptions::OpenTimeout.new, Errno::ECONNREFUSED.new, connect_failure(Errno::ECONNREFUSED.new),
     connect_failure(SocketError.new("getaddrinfo: Name or service not known")),
     connect_failure(Errno::EHOSTUNREACH.new), connect_failure(Errno::ENETUNREACH.new)]
  end

  # the request may have reached the console, and the reply was lost. Unreachable and socket
  # errors without the connect prefix happened on a connection already in use.
  def possibly_delivered_errors
    [RestClient::Exceptions::ReadTimeout.new, RestClient::ServerBrokeConnection.new, Errno::ECONNRESET.new,
     RestClient::InternalServerError.new(nil, 500), RestClient::BadGateway.new(nil, 502),
     Errno::EPIPE.new, IOError.new("closed stream"),
     Errno::EHOSTUNREACH.new, Errno::ENETUNREACH.new, SocketError.new("recvfrom: connection lost")]
  end

  # failures that are not a lost reply: the request was answered, or failed in a way a retry would
  # not fix. They are never retried, and reach the caller as they are.
  def never_retried_errors
    [OpenSSL::SSL::SSLError.new("SSL_read: unexpected eof while reading"),
     RestClient::SSLCertificateNotVerified.new("certificate verify failed"),
     RestClient::BadRequest.new(nil, 400), RestClient::RequestTimeout.new(nil, 408), RestClient::Conflict.new(nil, 409),
     RestClient::Exceptions::EXCEPTIONS_MAP.fetch(429).new(nil, 429)]
  end

  def test_a_request_that_never_reached_the_console_is_retried_for_any_action
    not_delivered_errors.each do |error|
      (["read"] + WRITES).each do |action|
        OPS.task_ids.clear
        console = FakeConsole.new(executes: [error], polls: [job("success", ok)])
        assert_equal true, ops(console).run(action, {"networkId" => 114})["success"], "#{action} after #{error.class}"
        assert_equal 2, console.executes.size, "#{action} after #{error.class}"
      end
    end
  end

  def test_a_request_that_never_reached_the_console_says_nothing_was_sent
    console = FakeConsole.new(executes: Array.new(5) { Errno::ECONNREFUSED.new })
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal :no_answer, err.kind
    assert_equal "not delivered", err.details[:delivery]
    assert_match(/nothing was sent/, err.message)
    assert_equal 5, console.executes.size
  end

  def test_a_request_that_may_have_reached_the_console_is_retried_only_for_reads
    possibly_delivered_errors.each do |error|
      OPS.task_ids.clear
      console = FakeConsole.new(executes: [error], polls: [job("success", ok)])
      assert_equal true, ops(console).run("read", {"networkId" => 114, "lbId" => "lb-1"})["success"], "read after #{error.class}"
      assert_equal 2, console.executes.size
      WRITES.each do |action|
        OPS.task_ids.clear
        console = FakeConsole.new(executes: [error], polls: [job("success", ok)])
        err = assert_raise(MtnCloud::Cli::LoadBalancerError, action) { ops(console).run(action, {"networkId" => 114}) }
        assert_equal :no_answer, err.kind
        assert_equal "no reply", err.details[:delivery]
        assert_match(/may have been applied: check the load balancer before trying again/, err.message)
        assert_equal 1, console.executes.size, "#{action} after #{error.class} must not be executed twice"
      end
    end
  end

  def test_a_timed_out_attempt_is_retried_only_for_reads
    # an attempt of 20 s polls 6 times (0.5, 1, 2, 4, 8, then the 4.5 s left)
    console = FakeConsole.new(polls: Array.new(6) { job("running") } + [job("success", ok)])
    o = ops(console)
    o.time_limits = {read_attempt: 20, read_total: 300}
    assert_equal true, o.run("read", {"networkId" => 114, "lbId" => "lb-1"})["success"]
    assert_equal 2, console.executes.size
    WRITES.each do |action|
      OPS.task_ids.clear
      console = FakeConsole.new(polls: Array.new(50) { job("running") })
      o = ops(console)
      o.time_limits = {write_attempt: 20, write_total: 900}
      err = assert_raise(MtnCloud::Cli::LoadBalancerError, action) { o.run(action, {"networkId" => 114}) }
      assert_equal :timed_out, err.kind
      assert_equal 1001, err.details[:job_execution_id]
      assert_match(/job execution 1001/, err.message)
      assert_match(/check the load balancer before trying again/, err.message)
      assert_equal 1, console.executes.size, "#{action} must not be executed again while its job may run"
    end
  end

  def test_a_whole_load_balancer_create_is_never_executed_twice_while_the_first_may_run
    request_id = OPS.new_request_id
    inputs = {"networkId" => 114, "requestId" => request_id,
              "spec" => {"name" => "web", "vipSubnetId" => "s1", "listeners" => [], "pools" => []}}
    created = ok({"loadbalancer" => {"id" => "lb-1", "provisioning_status" => "ACTIVE"}, "existing" => true})

    # the execute request may have reached the console
    console = FakeConsole.new(executes: [RestClient::Exceptions::ReadTimeout.new], polls: [job("success", created)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("create", inputs) }
    assert_equal :no_answer, err.kind
    assert_equal 1, console.executes.size

    # the attempt ran out of time while its job may still run
    OPS.task_ids.clear
    console = FakeConsole.new(polls: Array.new(50) { job("running") } + [job("success", created)])
    o = ops(console)
    o.time_limits = {write_attempt: 60, write_total: 900}
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { o.run("create", inputs) }
    assert_equal :timed_out, err.kind
    assert_equal 1, console.executes.size

    # the request never reached the console: nothing ran, so it is sent again with the same requestId
    OPS.task_ids.clear
    console = FakeConsole.new(executes: [RestClient::Exceptions::OpenTimeout.new], polls: [job("success", created)])
    ops(console).run("create", inputs)
    assert_equal 2, console.executes.size
    assert_equal [request_id] * 2, (0..1).collect {|n| console.payload(n)["job"]["customOptions"]["requestId"] }

    # the job ended without an answer: the first execution has finished, so a retry cannot overlap it
    OPS.task_ids.clear
    console = FakeConsole.new(polls: [job("error"), job("success", created)])
    assert_equal "lb-1", ops(console).run("create", inputs)["result"]["loadbalancer"]["id"]
    assert_equal 2, console.executes.size
    assert_equal [request_id] * 2, (0..1).collect {|n| console.payload(n)["job"]["customOptions"]["requestId"] }
  end

  def test_unreachable_and_socket_errors_count_as_not_delivered_only_in_the_connect_step
    [Errno::EHOSTUNREACH.new, Errno::ENETUNREACH.new, SocketError.new("getaddrinfo: Name or service not known")].each do |error|
      # raised while opening the connection: nothing was sent, so a write is sent again
      OPS.task_ids.clear
      console = FakeConsole.new(executes: [connect_failure(error)], polls: [job("success", ok)])
      assert_equal true, ops(console).run("pool-update", {"networkId" => 114})["success"], error.class.to_s
      assert_equal 2, console.executes.size
      # the same error on a connection already in use: the request may have arrived
      OPS.task_ids.clear
      console = FakeConsole.new(executes: [error], polls: [job("success", ok)])
      err = assert_raise(MtnCloud::Cli::LoadBalancerError, error.class.to_s) { ops(console).run("pool-update", {"networkId" => 114}) }
      assert_equal "no reply", err.details[:delivery]
      assert_equal 1, console.executes.size
    end
  end

  def test_failures_that_are_not_a_lost_reply_are_never_retried
    never_retried_errors.each do |error|
      %w[read create pool-update].each do |action|
        OPS.task_ids.clear
        console = FakeConsole.new(executes: [error], polls: [job("success", ok)])
        raised = assert_raise(error.class, "#{action} after #{error.class}") { ops(console).run(action, {"networkId" => 114}) }
        assert_same error, raised
        assert_equal 1, console.executes.size, "#{action} after #{error.class}"
      end
    end
  end

  def test_a_read_that_never_gets_a_reply_stops_after_its_retries
    console = FakeConsole.new(executes: Array.new(5) { RestClient::Exceptions::ReadTimeout.new })
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("read", {"networkId" => 114, "lbId" => "lb-1"}) }
    assert_equal :no_answer, err.kind
    assert_equal "no reply", err.details[:delivery]
    assert_equal "The console did not reply to the load balancer read request. Try again.", err.message
    assert_equal 5, console.executes.size
    assert_equal [5, 10, 20, 40], @waits
    assert_equal ["no reply"] * 5, err.details[:attempts].collect {|a| a[:delivery] }
  end

  # --- what earlier attempts may have done, after the retries run out ------------------

  def test_a_write_that_may_have_acted_earlier_is_not_reported_as_nothing_sent
    refused_connect = Array.new(4) { connect_failure(Errno::ECONNREFUSED.new) }
    # attempt 1: the job ended without an answer (it may have acted); attempts 2 to 5 never arrived
    console = FakeConsole.new(executes: [nil] + refused_connect, polls: [job("error")])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) do
      ops(console).run("create", {"networkId" => 114, "requestId" => OPS.new_request_id, "spec" => {"name" => "web"}})
    end
    assert_equal :no_answer, err.kind
    assert_equal "The load balancer create operation could not reach the console on its last attempt. " \
                 "An earlier attempt may have been applied. Check the load balancer before trying again.", err.message
    assert_no_match(/nothing was sent/, err.message)
    assert_equal true, err.details[:earlier_attempt_may_have_acted]
    attempts = err.details[:attempts]
    assert_equal 5, attempts.size
    assert_equal({attempt: 1, outcome: "error", delivery: "delivered", job_execution_id: 1001, may_have_acted: true}, attempts[0])
    assert_equal [NOT_DELIVERED_DETAIL] * 4, attempts[1..].collect {|a| a[:delivery] }
  end
  NOT_DELIVERED_DETAIL = "not delivered"

  def test_a_write_whose_earlier_attempts_did_nothing_is_not_reported_as_maybe_applied
    # attempt 1: the plugin answered that nothing ran; attempts 2 to 5 never arrived
    console = FakeConsole.new(executes: [nil] + Array.new(4) { RestClient::Exceptions::OpenTimeout.new }, polls: [job("error", INPUT_TIMEOUT)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal "The load balancer pool-update operation could not reach the console on its last attempt. Try again.", err.message
    assert_equal false, err.details[:earlier_attempt_may_have_acted]
    assert_equal false, err.details[:attempts][0][:may_have_acted]
  end

  def test_a_read_with_an_earlier_reply_lost_is_not_reported_as_nothing_sent
    console = FakeConsole.new(executes: [RestClient::Exceptions::ReadTimeout.new] + Array.new(4) { RestClient::Exceptions::OpenTimeout.new })
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("read", {"networkId" => 114, "lbId" => "lb-1"}) }
    assert_equal "The load balancer read operation could not reach the console on its last attempt. Try again.", err.message
    assert_equal %w[no\ reply not\ delivered not\ delivered not\ delivered not\ delivered], err.details[:attempts].collect {|a| a[:delivery] }
  end

  def test_an_error_after_earlier_attempts_keeps_their_history
    # attempt 1 never arrived, attempt 2's job ended without an answer, attempt 3's job is never found
    console = FakeConsole.new(executes: [RestClient::Exceptions::OpenTimeout.new], polls: [job("error")] + Array.new(10) { not_found })
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-delete", {"networkId" => 114, "poolId" => "p1"}) }
    assert_equal :job_not_found, err.kind
    assert_equal [false, true, true], err.details[:attempts].collect {|a| a[:may_have_acted] }
    assert_equal %w[not\ delivered error job_not_found], err.details[:attempts].collect {|a| a[:outcome] }
  end

  # --- a stale cached task id, then another failure ------------------------------------

  def test_after_a_stale_cached_task_id_an_uncertain_execute_is_not_repeated_for_a_write
    console = FakeConsole.new(polls: [job("success", ok)])
    ops(console).run("list", {"networkId" => 114})                                  # caches the task id
    console.instance_variable_get(:@executes).push(not_found, RestClient::Exceptions::ReadTimeout.new)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-update", {"networkId" => 114}) }
    assert_equal "no reply", err.details[:delivery]
    assert_equal 2, console.task_lookups.size                                       # looked up again once
    assert_equal 3, console.executes.size                                           # list, the stale id, one real try
  end

  def test_after_a_stale_cached_task_id_a_read_with_no_reply_is_retried
    console = FakeConsole.new(polls: [job("success", ok), job("success", ok)])
    ops(console).run("list", {"networkId" => 114})
    console.instance_variable_get(:@executes).push(not_found, RestClient::Exceptions::ReadTimeout.new)
    assert_equal true, ops(console).run("read", {"networkId" => 114, "lbId" => "lb-1"})["success"]
    assert_equal 4, console.executes.size                                           # list, stale, no reply, success
  end

  def test_after_a_stale_cached_task_id_a_write_that_never_arrived_is_retried
    console = FakeConsole.new(polls: [job("success", ok), job("success", ok)])
    ops(console).run("list", {"networkId" => 114})
    console.instance_variable_get(:@executes).push(not_found, connect_failure(Errno::ECONNREFUSED.new))
    assert_equal true, ops(console).run("pool-update", {"networkId" => 114})["success"]
    assert_equal 4, console.executes.size                                           # list, stale, refused connect, success
  end

  def test_a_whole_load_balancer_create_is_not_repeated_after_a_socket_error_on_a_used_connection
    console = FakeConsole.new(executes: [SocketError.new("recvfrom: connection lost")], polls: [job("success", ok)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) do
      ops(console).run("create", {"networkId" => 114, "requestId" => OPS.new_request_id, "spec" => {"name" => "web"}})
    end
    assert_equal "no reply", err.details[:delivery]
    assert_equal 1, console.executes.size
  end

  # --- refusals: what was taken back, what was left -----------------------------------

  def test_a_rolled_back_save_says_so
    answer = refused("Pool 'web': member 10.0.0.5:80 rejected - address in use", "rolledBack" => true)
    console = FakeConsole.new(polls: [job("success", answer)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-create", {"networkId" => 114}) }
    assert_equal true, err.rolled_back
    assert_equal "Pool 'web': member 10.0.0.5:80 rejected - address in use. What this change created was removed again, " \
                 "so you can try again from a clean state.", err.message
  end

  def test_a_rollback_marked_only_on_a_step_counts
    answer = refused("L7 rule PATH REGEX '^/x' is in ERROR", "result" => {"steps" => [{"kind" => "L7 policy", "rolledBack" => true}]})
    console = FakeConsole.new(polls: [job("success", answer)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("l7policy-create", {"networkId" => 114}) }
    assert_equal true, err.rolled_back
  end

  def test_what_a_failed_save_left_behind_is_kept_and_listed
    left = [{"kind" => "pool", "name" => "web", "id" => "p1", "error" => "could not delete"}, {"kind" => "listener", "name" => "http", "id" => "l1", "kept" => true}]
    console = FakeConsole.new(polls: [job("success", refused("save failed", "rolledBack" => true, "leftBehind" => left))])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-create", {"networkId" => 114}) }
    assert_equal left, err.left_behind
    assert_equal "save failed. Left on the load balancer: pool \"web\" (p1): could not delete; listener \"http\" (l1), kept. " \
                 "Check the load balancer before trying again.", err.message
  end

  def test_a_create_whose_piece_ended_in_error_keeps_its_id
    answer = refused("Pool p2 is in ERROR: the load balancer could not apply it.", "piece" => {"id" => "p2", "provisioning_status" => "ERROR"})
    console = FakeConsole.new(polls: [job("success", answer)])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-create", {"networkId" => 114}) }
    assert_equal "p2", err.piece_id
  end

  # --- message rewriting --------------------------------------------------------------

  def test_cloud_software_names_are_rewritten_and_details_are_kept
    cloud = 'openstack' # mtncloud:allow-cloud-name (test input for the rewriting)
    lbs = 'octavia' # mtncloud:allow-cloud-name (test input for the rewriting)
    vm = 'amphora' # mtncloud:allow-cloud-name (test input for the rewriting)
    camel = cloud.sub(/\Ao/, "O").sub("stack", "Stack")
    {
      "#{camel} refused port 8080 on subnet 5c1d (409)." => "The cloud refused port 8080 on subnet 5c1d (409).",
      "Saving failed in the #{camel} API: quota exceeded." => "Saving failed in the cloud API: quota exceeded.",
      "#{lbs.capitalize} could not create listener l1." => "the load balancer service could not create listener l1.",
      "#{vm.capitalize}e are still booting; #{vm} 7f is ERROR." => "load balancer VMs are still booting; load balancer VM 7f is ERROR.",
    }.each do |input, expected|
      assert_equal expected, OPS.customer_text(input)
    end
  end

  def test_refusal_messages_are_rewritten
    cloud = 'openstack' # mtncloud:allow-cloud-name (test input for the rewriting)
    console = FakeConsole.new(polls: [job("success", refused("#{cloud.capitalize} said no to pool p1."))])
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { ops(console).run("pool-create", {"networkId" => 114}) }
    assert_equal "The cloud said no to pool p1.", err.message
    assert_equal "#{cloud.capitalize} said no to pool p1.", err.details[:error], "the original stays in the details"
  end

  # --- dry run ------------------------------------------------------------------------

  def test_dry_run_sends_nothing_not_even_the_task_lookup
    o = OPS.new(url: "https://console.example.test", access_token: "token-a")
    o.dry_run(true)
    original = MtnCloud::RestClient.method(:execute)
    MtnCloud::RestClient.define_singleton_method(:execute) {|*args| raise "dry run must not send requests" }
    begin
      request = o.run("list", {"networkId" => 114})
    ensure
      MtnCloud::RestClient.define_singleton_method(:execute, original)
    end
    assert_equal :post, request[:method]
    assert_equal "https://console.example.test/api/tasks/{lboperate.terraform}/execute", request[:url]
    assert_equal({"action" => "list", "networkId" => "114"}, JSON.parse(request[:payload])["job"]["customOptions"])
    assert_empty OPS.task_ids
  end

  # --- how the CLI prints these errors ------------------------------------------------

  def test_the_error_handler_prints_the_message_without_a_usage_hint
    err = MtnCloud::Cli::LoadBalancerError.new("Pool p9 is not on this load balancer.", kind: :refused, action: "pool-update",
                                               details: {job_execution_id: 1001})
    out = StringIO.new
    exit_code, _ = MtnCloud::Cli::ErrorHandler.new(out).handle_error(err)
    assert_equal 1, exit_code
    assert_include out.string, "Pool p9 is not on this load balancer."
    assert_not_include out.string, "Try --help"
    assert_not_include out.string, "1001"
    out = StringIO.new
    MtnCloud::Cli::ErrorHandler.new(out).handle_error(err, {debug: true})
    assert_include out.string, "\"job_execution_id\":1001"
  end
end
