require 'lb_test_support'

# Dry runs of the load balancer commands through the real Load Balancer Operations interface, so
# the request checked is the one the CLI prints. Nothing may be sent: any request, the network
# lookup, or loading (and so refreshing) saved credentials fails the test.
class LoadBalancerDryRunTest < Test::Unit::TestCase
  include LbTestSupport

  class NoNetworkLookup
    def list(*_args)
      raise "a dry run must not look up the network"
    end
  end

  def setup
    @original_execute = MtnCloud::RestClient.method(:execute)
    MtnCloud::RestClient.define_singleton_method(:execute) {|*_args| raise "a dry run must not send requests" }
  end

  def teardown
    MtnCloud::RestClient.define_singleton_method(:execute, @original_execute)
  end

  def dry_command(klass)
    ops = MtnCloud::APIClient.new('dry-run-token', nil, nil, 'https://console.example.test').load_balancer_operations
    nets = NoNetworkLookup.new
    command = klass.new
    command.define_singleton_method(:establish_remote_appliance_connection) do |_options|
      raise "a dry run test must not load or refresh credentials"
    end
    command.define_singleton_method(:lb_connect) do |_options|
      @load_balancer_operations_interface = ops
      @networks_interface = nets
      @lb_reads = {}
    end
    command
  end

  # The printed request: its URL and the job's custom options, parsed from the JSON it shows.
  def printed_request(output)
    url = output[/^POST (\S+)$/, 1]
    json = output[/^JSON\n(\{.*\})/m, 1]
    assert_not_nil json, output
    [url, JSON.parse(json)['job']]
  end

  def test_a_network_name_is_shown_unresolved_and_never_looked_up
    output, result = capture_output { dry_command(MtnCloud::Cli::LoadBalancers).list(['--network', 'app-net', '-d']) }
    assert_equal [0, nil], result
    url, job = printed_request(output)
    assert_equal 'https://console.example.test/api/tasks/{lboperate.terraform}/execute', url
    assert_equal 'appliance', job['targetType']
    assert_equal({'action' => 'list', 'networkId' => '<unresolved network name: app-net>'}, job['customOptions'])
  end

  def test_a_numeric_network_id_is_shown_as_it_is
    output, = capture_output { dry_command(MtnCloud::Cli::LoadBalancers).get([LB_ID, '--network', '114', '-d']) }
    _url, job = printed_request(output)
    assert_equal({'action' => 'read', 'networkId' => '114', 'lbId' => LB_ID}, job['customOptions'])
  end

  def test_every_command_prints_its_request_and_sends_nothing
    [[MtnCloud::Cli::LoadBalancers, :list, ['--name', 'web-lb', '--page', '2', '--page-size', '50'],
      {'action' => 'list', 'name' => 'web-lb', 'page' => '2', 'pageSize' => '50'}],
     [MtnCloud::Cli::LoadBalancers, :floating_ip_options, [], {'action' => 'fip-options'}],
     [MtnCloud::Cli::LoadBalancerListeners, :get, ['web-lb', 'http'], {'action' => 'read', 'name' => 'web-lb'}],
     [MtnCloud::Cli::LoadBalancerPools, :list, ['web-lb'], {'action' => 'read', 'name' => 'web-lb'}],
     [MtnCloud::Cli::LoadBalancerMembers, :get, ['web-lb', 'web', 'mem-1'], {'action' => 'read', 'name' => 'web-lb'}],
     [MtnCloud::Cli::LoadBalancerMonitors, :list, [LB_ID], {'action' => 'read', 'lbId' => LB_ID}],
     [MtnCloud::Cli::LoadBalancerL7Policies, :list, ['web-lb', 'http'], {'action' => 'read', 'name' => 'web-lb'}]].each do |klass, sub, args, inputs|
      output, result = capture_output { dry_command(klass).send(sub, args + ['--network', 'app-net', '-d']) }
      assert_equal [0, nil], result, "#{klass} #{sub}"
      _url, job = printed_request(output)
      assert_equal inputs.merge('networkId' => '<unresolved network name: app-net>'), job['customOptions'], "#{klass} #{sub}"
    end
  end
end
