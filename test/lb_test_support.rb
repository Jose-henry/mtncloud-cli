require 'test/unit'
require 'stringio'
require 'mtncloud'

# Shared fixtures for the load balancer command tests: a scripted Load Balancer Operations
# interface, a scripted networks interface, and answers shaped like the plugin's.
module LbTestSupport

  LB_ID = '6f1c2d3e-4b5a-4c7d-8e9f-0a1b2c3d4e5f'
  OTHER_LB_ID = '7a2b3c4d-5e6f-4a8b-9c0d-1e2f3a4b5c6d'
  CERT_REF = 'https://certs.example.net/v1/containers/0b1c2d3e'
  SNI_REF = 'https://certs.example.net/v1/containers/9f8e7d6c'

  # Records every run and answers from a script: an answer, a lambda taking the inputs, or an
  # error to raise. In dry run mode it returns the execute request, as the real interface does.
  class FakeOperations
    attr_reader :runs, :setopts_calls

    def initialize(answers = {})
      @answers = answers
      @runs = []
      @setopts_calls = []
      @dry = false
    end

    def setopts(options)
      @setopts_calls << options
      @dry = !!options[:dry_run]
      self
    end

    def run(action, inputs = {})
      @runs << [action, inputs]
      if @dry
        opts = {"action" => action}
        inputs.each {|k, v| opts[k.to_s] = v.to_s }
        return {method: :post, url: "/api/tasks/{lboperate.terraform}/execute",
                payload: {"job" => {"targetType" => "appliance", "customOptions" => opts}}}
      end
      answer = @answers[action]
      raise "no scripted answer for #{action}" if answer.nil?
      raise answer if answer.is_a?(Exception)
      answer.respond_to?(:call) ? answer.call(inputs) : answer
    end
  end

  class FakeNetworks
    attr_reader :list_calls

    def initialize(networks = [])
      @networks = networks
      @list_calls = []
    end

    def list(params = {})
      @list_calls << params
      {'networks' => @networks.select {|n| n['name'] == params[:name] }}
    end
  end

  def refused(msg, action = 'read')
    MtnCloud::Cli::LoadBalancerError.new(msg, kind: :refused, action: action, details: {error: msg})
  end

  # ---------------------------------------------------------------------------------------------
  # Fixtures, shaped like the plugin's own answers (its read is the cloud's object, expanded and
  # annotated). Each method below is what a CUSTOMER may see of that object; read_answer and
  # list_answer add what the plugin and the cloud send besides, which the CLI must remove.
  # ---------------------------------------------------------------------------------------------

  PROJECT_ID = '9c1e2f4a6b8d4c0e8f1a2b3c4d5e6f70'
  # What the plugin sends that customers never see. Its provider value is the cloud's load
  # balancer driver on a live read, and the cloud software's name on a stored list row.
  PROVIDER_LIVE = 'amphora' # mtncloud:allow-cloud-name (cloud provider value the plugin sends)
  PROVIDER_STORED = 'octavia' # mtncloud:allow-cloud-name (cloud provider value the plugin sends)
  ORIGIN_FIELD = 'morpheus_origin' # mtncloud:allow-upstream-name (plugin member field the CLI hides)
  INSTANCE_MEMBER_TAGS = ['morpheus:instance', 'morpheus:group:41', 'morpheus:gw:1'] # mtncloud:allow-upstream-name (plugin member tags the CLI hides)
  CLUSTER_MEMBER_TAGS = ['morpheus:instance', 'morpheus:group:cluster:7:worker'] # mtncloud:allow-upstream-name (plugin member tags the CLI hides)
  EXTERNAL_MEMBER_TAG = 'morpheus:external' # mtncloud:allow-upstream-name (plugin member tag the CLI hides)
  CLOUD_ERROR = 'List members failed: octavia returned 503' # mtncloud:allow-cloud-name (a cloud error the plugin passes on)

  def listener_http
    {
      'id' => 'lis-80', 'name' => 'http', 'description' => '', 'protocol' => 'HTTP', 'protocol_port' => 80,
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'connection_limit' => -1, 'default_pool_id' => 'pool-web', 'default_tls_container_ref' => nil,
      'sni_container_refs' => [], 'allowed_cidrs' => [], 'timeout_client_data' => 50000,
      'timeout_member_connect' => 5000, 'timeout_member_data' => 50000, 'timeout_tcp_inspect' => 0,
      'insert_headers' => {'X-Forwarded-For' => 'true'}, 'loadbalancers' => [{'id' => LB_ID}],
      'l7policies' => [{'id' => 'pol-2'}, {'id' => 'pol-1'}], 'created_at' => '2026-11-01T10:01:00',
      'updated_at' => '2026-11-02T10:00:00', 'tags' => ['team-web'],
      'l7policies_expanded' => [
        {'id' => 'pol-2', 'name' => 'api', 'description' => '', 'action' => 'REDIRECT_TO_POOL', 'position' => 2,
         'listener_id' => 'lis-80', 'redirect_pool_id' => 'pool-api', 'redirect_url' => nil, 'redirect_prefix' => nil,
         'redirect_http_code' => nil, 'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE',
         'admin_state_up' => true, 'rules' => [{'id' => 'rule-1'}], 'tags' => [],
         'rules_expanded' => [{'id' => 'rule-1', 'type' => 'PATH', 'compare_type' => 'STARTS_WITH', 'key' => nil,
                               'value' => '/api', 'invert' => false, 'admin_state_up' => true,
                               'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'tags' => []}]},
        {'id' => 'pol-1', 'name' => 'old', 'description' => '', 'action' => 'REDIRECT_TO_URL', 'position' => 1,
         'listener_id' => 'lis-80', 'redirect_pool_id' => nil, 'redirect_url' => 'https://example.net',
         'redirect_prefix' => nil, 'redirect_http_code' => 302, 'provisioning_status' => 'ACTIVE',
         'operating_status' => 'ONLINE', 'admin_state_up' => true, 'rules' => [], 'tags' => [], 'rules_expanded' => []}
      ]
    }
  end

  def listener_https
    {
      'id' => 'lis-443', 'name' => 'https', 'description' => '', 'protocol' => 'TERMINATED_HTTPS', 'protocol_port' => 443,
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'connection_limit' => 1000, 'default_pool_id' => 'pool-web', 'default_tls_container_ref' => CERT_REF,
      'sni_container_refs' => [SNI_REF], 'allowed_cidrs' => ['203.0.113.0/24'], 'insert_headers' => {},
      'loadbalancers' => [{'id' => LB_ID}], 'l7policies' => [], 'created_at' => '2026-11-01T10:02:00',
      'updated_at' => '2026-11-01T10:02:00', 'tags' => [], 'l7policies_expanded' => []
    }
  end

  def pool_web
    {
      'id' => 'pool-web', 'name' => 'web', 'description' => '', 'protocol' => 'HTTP', 'lb_algorithm' => 'ROUND_ROBIN',
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'DEGRADED', 'admin_state_up' => true,
      'session_persistence' => {'type' => 'APP_COOKIE', 'cookie_name' => 'sid'}, 'tls_enabled' => false,
      'healthmonitor_id' => 'mon-web', 'listeners' => [{'id' => 'lis-80'}], 'loadbalancers' => [{'id' => LB_ID}],
      'created_at' => '2026-11-01T10:03:00', 'updated_at' => '2026-11-01T10:03:00', 'tags' => [],
      'members' => [
        # added from instance 41 as a group member: the plugin tags it and names its instance
        {'id' => 'mem-2', 'name' => '', 'address' => '10.0.0.12', 'protocol_port' => 8080, 'weight' => 1, 'backup' => false,
         'subnet_id' => 'sub-1', 'monitor_address' => nil, 'monitor_port' => nil, 'provisioning_status' => 'ACTIVE',
         'operating_status' => 'ONLINE', 'admin_state_up' => true, 'created_at' => '2026-11-01T10:04:00',
         'updated_at' => '2026-11-01T10:04:00', 'tags' => [], 'orphaned' => false, 'instanceId' => 41},
        # added by address: the plugin tags it as external and never flags it
        {'id' => 'mem-1', 'name' => 'app-1', 'address' => '10.0.0.11', 'protocol_port' => 8080, 'weight' => 2, 'backup' => false,
         'subnet_id' => 'sub-1', 'monitor_address' => nil, 'monitor_port' => nil, 'provisioning_status' => 'ACTIVE',
         'operating_status' => 'ERROR', 'admin_state_up' => true, 'created_at' => '2026-11-01T10:04:30',
         'updated_at' => '2026-11-01T10:04:30', 'tags' => ['blue'], 'orphaned' => false},
        # a cluster node added as part of a cluster group
        {'id' => 'mem-3', 'name' => 'node-7a', 'address' => '10.0.0.13', 'protocol_port' => 8080, 'weight' => 1, 'backup' => true,
         'subnet_id' => 'sub-1', 'monitor_address' => nil, 'monitor_port' => nil, 'provisioning_status' => 'ACTIVE',
         'operating_status' => 'ONLINE', 'admin_state_up' => true, 'created_at' => '2026-11-01T10:05:00',
         'updated_at' => '2026-11-01T10:05:00', 'tags' => [], 'orphaned' => false}
      ],
      'healthmonitor' => {'id' => 'mon-web', 'name' => 'web-check', 'type' => 'HTTP', 'delay' => 5, 'timeout' => 3,
                          'max_retries' => 3, 'max_retries_down' => 3, 'http_method' => 'GET', 'url_path' => '/health',
                          'expected_codes' => '200', 'admin_state_up' => true, 'provisioning_status' => 'ACTIVE',
                          'operating_status' => 'ONLINE', 'pools' => [{'id' => 'pool-web'}], 'tags' => []}
    }
  end

  def pool_api
    {
      'id' => 'pool-api', 'name' => 'api', 'description' => '', 'protocol' => 'HTTP', 'lb_algorithm' => 'LEAST_CONNECTIONS',
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'session_persistence' => nil, 'tls_enabled' => false, 'healthmonitor_id' => nil, 'listeners' => [],
      'loadbalancers' => [{'id' => LB_ID}], 'created_at' => '2026-11-01T10:06:00', 'updated_at' => '2026-11-01T10:06:00',
      'members' => [], 'tags' => []
    }
  end

  # The load balancer a customer sees: the cloud's own fields the CLI keeps, and the plugin's
  # health_problems (what is in ERROR or OFFLINE).
  def visible_load_balancer(overrides = {})
    {
      'id' => LB_ID, 'name' => 'web-lb', 'description' => 'front door', 'provisioning_status' => 'ACTIVE',
      'operating_status' => 'DEGRADED', 'admin_state_up' => true, 'vip_address' => '10.0.0.5',
      'vip_subnet_id' => 'sub-1', 'vip_network_id' => 'net-1', 'vip_port_id' => 'port-1', 'vip_qos_policy_id' => nil,
      'flavor_id' => 'flv-small', 'availability_zone' => 'az-1', 'tags' => ['prod'],
      'created_at' => '2026-11-01T10:00:00', 'updated_at' => '2026-11-02T10:00:00',
      'listeners' => [listener_https, listener_http], 'pools' => [pool_web, pool_api],
      'health_problems' => [{'kind' => 'member', 'name' => '10.0.0.11:8080', 'parent' => 'web',
                             'operating_status' => 'ERROR', 'provisioning_status' => 'ACTIVE'}],
      'vip_subnet_display' => 'app-subnet (10.0.0.0/24)'
    }.merge(overrides)
  end

  # What the plugin's read sends for that load balancer: the same, plus the cloud project, the
  # provider, the plugin's diagnostics, its member origin field and its own tags.
  def plugin_load_balancer(visible)
    lb = JSON.parse(JSON.generate(visible))
    cloud = ->(o) { o.merge!('project_id' => PROJECT_ID, 'tenant_id' => PROJECT_ID) if o.is_a?(Hash) }
    cloud.(lb)
    lb['provider'] = PROVIDER_LIVE
    lb['health_checked'] = {'tree_keys' => ['loadbalancer'], 'listeners' => 2, 'pools_matched' => 2}
    lb['tags'] = ['mtncloud-req-cli00aa'] + lb['tags'].to_a
    (lb['listeners'] || []).each do |l|
      cloud.(l)
      l['tags'] = ['mtncloud-req-cli0011'] + l['tags'].to_a if l['id'] == 'lis-80'
      (l['l7policies_expanded'] || []).each {|p| cloud.(p); (p['rules_expanded'] || []).each(&cloud) }
    end
    (lb['pools'] || []).each do |p|
      cloud.(p)
      cloud.(p['healthmonitor'])
      (p['members'] || []).each do |m|
        cloud.(m)
        case m['id']
        when 'mem-2' then m[ORIGIN_FIELD] = 'instance'; m['tags'] = INSTANCE_MEMBER_TAGS + m['tags'].to_a
        when 'mem-1' then m[ORIGIN_FIELD] = 'external'; m['tags'] = [EXTERNAL_MEMBER_TAG] + m['tags'].to_a
        when 'mem-3' then m[ORIGIN_FIELD] = 'instance'; m['tags'] = CLUSTER_MEMBER_TAGS + m['tags'].to_a
        else m[ORIGIN_FIELD] = nil
        end
      end
    end
    lb
  end

  # The task's whole answer to `read`: its envelope, and the route's own answer as the result.
  def read_answer(lb_overrides = {}, can_manage: true, network_access: 'owner')
    {'success' => true, 'action' => 'read', 'caller' => {'userId' => 7, 'username' => 'ada', 'accountId' => 3},
     'permissionSource' => 'task-access', 'networkAccess' => network_access,
     'result' => {'success' => true, 'loadbalancer' => plugin_load_balancer(visible_load_balancer(lb_overrides)),
                  'canManage' => can_manage}}
  end

  # What `get --json` must show for that answer.
  def visible_read_result(lb_overrides = {}, can_manage: true, network_access: 'owner')
    {'loadbalancer' => visible_load_balancer(lb_overrides), 'canManage' => can_manage, 'networkAccess' => network_access}
  end

  # A list row as a customer sees it.
  def list_row(overrides = {})
    {'id' => LB_ID, 'name' => 'web-lb', 'vip_address' => '10.0.0.5', 'vip_subnet_id' => 'sub-1',
     'vip_network_id' => 'net-1', 'vip_floating' => '198.51.100.7', 'vip_floating_known' => true,
     'vip_display' => '10.0.0.5/198.51.100.7', 'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE',
     'description' => '', 'created_at' => '2026-11-01T10:00:00', 'membersCount' => 3, 'membersKnown' => true,
     'networkId' => 114, 'networkName' => 'app-net'}.merge(overrides)
  end

  # The task's answer to `list` from the plugin's stored list (the default), in the plugin's own
  # order: oldest first. Each row carries the provider; the result carries the route's success
  # flag and how fresh the stored list is.
  def list_answer(rows = nil, extra = {}, network_access: 'owner', can_manage: true)
    rows ||= [list_row, list_row('id' => OTHER_LB_ID, 'name' => 'api-lb', 'vip_floating' => nil, 'vip_floating_known' => false,
                                 'vip_display' => '10.0.0.6', 'vip_address' => '10.0.0.6', 'membersCount' => nil,
                                 'membersKnown' => false, 'created_at' => '2026-11-03T09:00:00')]
    rows = rows.collect {|r| r.merge('provider' => PROVIDER_STORED) }
    {'success' => true, 'action' => 'list', 'caller' => {'userId' => 7}, 'permissionSource' => 'task-access',
     'networkAccess' => network_access,
     'result' => {'success' => true, 'loadbalancers' => rows, 'total' => rows.size, 'canManage' => can_manage,
                  'fresh' => false, 'source' => 'store', 'stale' => false, 'ageMs' => 1200}.merge(extra)}
  end

  def fip_answer
    {'success' => true, 'action' => 'fip-options', 'networkAccess' => 'owner',
     'result' => {'success' => true,
                  'floatingIpPools' => [{'name' => 'public-b', 'externalId' => 'ext-b'}, {'name' => 'public-a', 'externalId' => 'ext-a'}],
                  'availableFloatingIps' => [{'id' => 'fip-2', 'address' => '198.51.100.9'}, {'id' => 'fip-1', 'address' => '198.51.100.8'}]}}
  end

  # Builds a command with scripted interfaces. Nothing connects to a remote.
  def build_lb_command(klass, answers = {}, networks: [])
    ops = FakeOperations.new(answers)
    nets = FakeNetworks.new(networks)
    command = klass.new
    # tables drop the columns that do not fit the console, and a CI runner has none (width 0):
    # give every command a wide one, so table tests see every column wherever they run
    command.define_singleton_method(:current_terminal_width) { 300 }
    command.define_singleton_method(:lb_connect) do |_options|
      @load_balancer_operations_interface = ops
      @networks_interface = nets
      @lb_reads = {}
    end
    [command, ops, nets]
  end

  def capture_output
    terminal = MtnCloud::Terminal.instance
    original = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    result = yield
    [buffer.string, result]
  ensure
    terminal.set_stdout(original)
  end

  def strip_color(s)
    s.gsub(/\e\[[\d;]*m/, '')
  end

  # Text that must never reach a customer: run details, freshness details, plugin tags, the cloud
  # provider's name and the names the CLI never shows.
  HIDDEN = [/permissionSource/, /"caller"/, /ageMs/, /"fresh"/, /"stale"/, /"source"/, /"provider"/, /"success"/,
            /provider:/, /success:/, /project_id/, /tenant_id/, /health_checked/, /health_error/, /_origin/,
            /mtncloud-req-/, /group:/, /gw:/, /external/, /instance/,
            Regexp.new('morpheus|openstack|octavia|amphora', Regexp::IGNORECASE)] # mtncloud:allow-cloud-name (names the output scan rejects) mtncloud:allow-upstream-name (names the output scan rejects)

  def assert_nothing_hidden(output)
    HIDDEN.each {|re| assert_no_match(re, output) }
  end
end
