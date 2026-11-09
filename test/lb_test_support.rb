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

  def listener_http
    {
      'id' => 'lis-80', 'name' => 'http', 'description' => '', 'protocol' => 'HTTP', 'protocol_port' => 80,
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'connection_limit' => -1, 'default_pool_id' => 'pool-web', 'default_tls_container_ref' => nil,
      'sni_container_refs' => [], 'allowed_cidrs' => [], 'timeout_client_data' => 50000,
      'timeout_member_connect' => 5000, 'timeout_member_data' => 50000, 'timeout_tcp_inspect' => 0,
      'tags' => ['mtncloud-req-cli0011', 'team-web'],
      'l7policies_expanded' => [
        {'id' => 'pol-2', 'name' => 'api', 'action' => 'REDIRECT_TO_POOL', 'position' => 2, 'redirect_pool_id' => 'pool-api',
         'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true, 'tags' => [],
         'rules_expanded' => [{'id' => 'rule-1', 'type' => 'PATH', 'compare_type' => 'STARTS_WITH', 'value' => '/api',
                               'invert' => false, 'admin_state_up' => true}]},
        {'id' => 'pol-1', 'name' => 'old', 'action' => 'REDIRECT_TO_URL', 'position' => 1, 'redirect_url' => 'https://example.net',
         'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true, 'tags' => [],
         'rules_expanded' => []}
      ]
    }
  end

  def listener_https
    {
      'id' => 'lis-443', 'name' => 'https', 'protocol' => 'TERMINATED_HTTPS', 'protocol_port' => 443,
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'connection_limit' => 1000, 'default_pool_id' => 'pool-web', 'default_tls_container_ref' => CERT_REF,
      'sni_container_refs' => [SNI_REF], 'allowed_cidrs' => ['203.0.113.0/24'], 'tags' => [],
      'l7policies_expanded' => []
    }
  end

  def pool_web
    {
      'id' => 'pool-web', 'name' => 'web', 'protocol' => 'HTTP', 'lb_algorithm' => 'ROUND_ROBIN',
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'session_persistence' => {'type' => 'APP_COOKIE', 'cookie_name' => 'sid'}, 'tls_enabled' => false,
      'listeners' => [{'id' => 'lis-80'}], 'tags' => [],
      'members' => [
        {'id' => 'mem-2', 'name' => '', 'address' => '10.0.0.12', 'protocol_port' => 8080, 'weight' => 1, 'backup' => false,
         'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
         'tags' => ['morpheus:group:41']}, # mtncloud:allow-upstream-name (plugin member group tag fixture)
        {'id' => 'mem-1', 'name' => 'app-1', 'address' => '10.0.0.11', 'protocol_port' => 8080, 'weight' => 2, 'backup' => false,
         'provisioning_status' => 'ACTIVE', 'operating_status' => 'ERROR', 'admin_state_up' => true, 'tags' => ['blue']}
      ],
      'healthmonitor' => {'id' => 'mon-web', 'name' => 'web-check', 'type' => 'HTTP', 'delay' => 5, 'timeout' => 3,
                          'max_retries' => 3, 'max_retries_down' => 3, 'http_method' => 'GET', 'url_path' => '/health',
                          'expected_codes' => '200', 'admin_state_up' => true, 'provisioning_status' => 'ACTIVE',
                          'operating_status' => 'ONLINE', 'tags' => []}
    }
  end

  def pool_api
    {
      'id' => 'pool-api', 'name' => 'api', 'protocol' => 'HTTP', 'lb_algorithm' => 'LEAST_CONNECTIONS',
      'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE', 'admin_state_up' => true,
      'members' => [], 'healthmonitor' => nil, 'listeners' => [], 'tags' => []
    }
  end

  def read_answer(lb_overrides = {}, can_manage: true, network_access: 'owner')
    lb = {
      'id' => LB_ID, 'name' => 'web-lb', 'description' => 'front door', 'provisioning_status' => 'ACTIVE',
      'operating_status' => 'ONLINE', 'admin_state_up' => true, 'vip_address' => '10.0.0.5',
      'vip_subnet_id' => 'sub-1', 'vip_subnet_display' => 'app-subnet (10.0.0.0/24)', 'vip_network_id' => 'net-1',
      'vip_port_id' => 'port-1', 'tags' => ['mtncloud-req-cli00aa', 'prod'], 'created_at' => '2026-11-01T10:00:00Z',
      'updated_at' => '2026-11-02T10:00:00Z',
      'listeners' => [listener_https, listener_http], 'pools' => [pool_web, pool_api]
    }.merge(lb_overrides)
    {'success' => true, 'action' => 'read', 'caller' => {'userId' => 7, 'username' => 'ada', 'accountId' => 3},
     'permissionSource' => 'task-access', 'networkAccess' => network_access,
     'result' => {'loadbalancer' => lb, 'canManage' => can_manage}}
  end

  def list_row(overrides = {})
    {'id' => LB_ID, 'name' => 'web-lb', 'description' => '', 'provisioning_status' => 'ACTIVE', 'operating_status' => 'ONLINE',
     'vip_address' => '10.0.0.5', 'vip_display' => '10.0.0.5', 'vip_floating' => '198.51.100.7', 'vip_floating_known' => true,
     'vip_network_id' => 'net-1', 'vip_subnet_id' => 'sub-1', 'membersCount' => 2, 'membersKnown' => true,
     'networkId' => 114, 'networkName' => 'app-net', 'created_at' => '2026-11-01T10:00:00Z',
     'provider' => 'amphora'}.merge(overrides) # mtncloud:allow-cloud-name (cloud provider value the CLI hides)
  end

  def list_answer(rows = nil, extra = {}, network_access: 'owner', can_manage: true)
    rows ||= [list_row('id' => OTHER_LB_ID, 'name' => 'api-lb', 'vip_floating' => nil, 'vip_floating_known' => false,
                       'membersKnown' => false), list_row]
    {'success' => true, 'action' => 'list', 'caller' => {'userId' => 7}, 'permissionSource' => 'task-access',
     'networkAccess' => network_access,
     'result' => {'loadbalancers' => rows, 'total' => rows.size, 'canManage' => can_manage,
                  'fresh' => true, 'stale' => false, 'ageMs' => 1200, 'source' => 'stored'}.merge(extra)}
  end

  def fip_answer
    {'success' => true, 'action' => 'fip-options', 'networkAccess' => 'owner',
     'result' => {'floatingIpPools' => [{'name' => 'public-b', 'externalId' => 'ext-b'}, {'name' => 'public-a', 'externalId' => 'ext-a'}],
                  'availableFloatingIps' => [{'id' => 'fip-2', 'address' => '198.51.100.9'}, {'id' => 'fip-1', 'address' => '198.51.100.8'}]}}
  end

  # Builds a command with scripted interfaces. Nothing connects to a remote.
  def build_lb_command(klass, answers = {}, networks: [])
    ops = FakeOperations.new(answers)
    nets = FakeNetworks.new(networks)
    command = klass.new
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
            /mtncloud-req-/, /group:41/,
            Regexp.new('morpheus|openstack|octavia|amphora', Regexp::IGNORECASE)] # mtncloud:allow-cloud-name (names the output scan rejects) mtncloud:allow-upstream-name (names the output scan rejects)

  def assert_nothing_hidden(output)
    HIDDEN.each {|re| assert_no_match(re, output) }
  end
end
