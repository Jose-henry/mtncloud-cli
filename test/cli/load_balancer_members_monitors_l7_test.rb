require 'lb_test_support'

# Unit tests for `mtncloud load-balancer-members`, `load-balancer-monitors` and
# `load-balancer-l7-policies`: every command is one `read` of the load balancer.
class LoadBalancerMembersMonitorsL7Test < Test::Unit::TestCase
  include LbTestSupport

  def command_for(klass, answer = read_answer)
    build_lb_command(klass, {'read' => answer}, networks: [{'id' => 114, 'name' => 'app-net'}])
  end

  ## members

  def test_members_list_sorted_by_address
    command, ops = command_for(MtnCloud::Cli::LoadBalancerMembers)
    output, = capture_output { command.list(['web-lb', 'web', '--network', '114']) }
    assert_equal [['read', {'networkId' => '114', 'name' => 'web-lb'}]], ops.runs
    text = strip_color(output)
    assert_match(/Members of Pool web/, text)
    assert_operator text.index('10.0.0.11'), :<, text.index('10.0.0.12')
    assert_nothing_hidden(output)
  end

  def test_members_list_json_drops_the_group_tag_and_keeps_the_rest
    command, = command_for(MtnCloud::Cli::LoadBalancerMembers)
    output, = capture_output { command.list(['web-lb', 'pool-web', '--network', '114', '-j']) }
    members = JSON.parse(output)['members']
    assert_equal ['mem-1', 'mem-2'], members.collect {|m| m['id'] }
    assert_equal pool_web['members'][1].keys, members[0].keys
    assert_equal [], members[1]['tags']
    assert_nothing_hidden(output)
  end

  def test_member_get_by_id_and_by_name
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerMembers)[0].get(['web-lb', 'web', 'mem-2', '--network', '114']) }
    text = strip_color(output)
    assert_match(/Address: 10\.0\.0\.12/, text)
    assert_match(/Pool: web \(pool-web\)/, text)
    assert_nothing_hidden(output)
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerMembers)[0].get(['web-lb', 'web', 'app-1', '--network', '114', '-j']) }
    assert_equal 'mem-1', JSON.parse(output)['member']['id']
  end

  def test_unknown_pool_or_member
    command, = command_for(MtnCloud::Cli::LoadBalancerMembers)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.list(['web-lb', 'nope', '--network', '114']) }
    assert_match(/no pool with the ID or name "nope"/, err.message)
    command, = command_for(MtnCloud::Cli::LoadBalancerMembers)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.get(['web-lb', 'web', '10.0.0.11', '--network', '114']) }
    assert_match(/no member with the ID or name "10\.0\.0\.11"/, err.message)
  end

  ## monitors

  def test_monitors_list
    command, ops = command_for(MtnCloud::Cli::LoadBalancerMonitors)
    output, = capture_output { command.list(['web-lb', '--network', '114']) }
    assert_equal 1, ops.runs.size
    text = strip_color(output)
    assert_match(/web-check/, text)
    assert_match(/web \(pool-web\)/, text)
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerMonitors)[0].list(['web-lb', '--network', '114', '-j']) }
    monitors = JSON.parse(output)['monitors']
    assert_equal ['mon-web'], monitors.collect {|m| m['id'] }
    assert_equal 'pool-web', monitors[0]['pool_id']
  end

  def test_monitor_get
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerMonitors)[0].get(['web-lb', 'web-check', '--network', '114']) }
    text = strip_color(output)
    assert_match(/URL Path: \/health/, text)
    assert_match(/Expected Codes: 200/, text)
    assert_nothing_hidden(output)
  end

  def test_no_monitors
    answer = read_answer({'pools' => [pool_api]})
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerMonitors, answer)[0].list(['web-lb', '--network', '114']) }
    assert_match(/No health monitors\./, strip_color(output))
  end

  def test_monitor_writes_are_not_available
    {add: /Adding a health monitor isn't available/, update: /Changing a health monitor/, remove: /Deleting a health monitor/}.each do |sub, msg|
      command, ops = command_for(MtnCloud::Cli::LoadBalancerMonitors)
      err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.send(sub, ['web-lb', '--network', '114']) }
      assert_equal :unavailable, err.kind
      assert_match msg, err.message
      assert_empty ops.runs
    end
  end

  ## L7 policies

  def test_l7_policies_list_in_position_order
    command, ops = command_for(MtnCloud::Cli::LoadBalancerL7Policies)
    output, = capture_output { command.list(['web-lb', 'http', '--network', '114']) }
    assert_equal 1, ops.runs.size
    text = strip_color(output)
    assert_operator text.index('pol-1'), :<, text.index('pol-2')
    assert_match(/api \(pool-api\)/, text)
    assert_match(/https:\/\/example\.net/, text)
  end

  def test_l7_policy_get_with_rules
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerL7Policies)[0].get(['web-lb', 'http', 'api', '--network', '114']) }
    text = strip_color(output)
    assert_match(/Rules/, text)
    assert_match(/STARTS_WITH/, text)
    assert_match(/\/api/, text)
    output, = capture_output { command_for(MtnCloud::Cli::LoadBalancerL7Policies)[0].get(['web-lb', 'http', 'pol-2', '--network', '114', '-j']) }
    policy = JSON.parse(output)['l7policy']
    assert_equal 'rule-1', policy['rules_expanded'][0]['id']
  end

  def test_l7_policies_that_could_not_be_read_are_an_error
    answer = read_answer
    answer['result']['loadbalancer']['listeners'][1]['l7policies_error'] = 'timed out'
    command, = command_for(MtnCloud::Cli::LoadBalancerL7Policies, answer)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.list(['web-lb', 'http', '--network', '114']) }
    assert_equal "The listener's L7 policies could not be read: timed out. Run the command again.", err.message
  end

  def test_several_l7_policies_with_one_name
    answer = read_answer
    answer['result']['loadbalancer']['listeners'][1]['l7policies_expanded'][1]['name'] = 'api'
    command, = command_for(MtnCloud::Cli::LoadBalancerL7Policies, answer)
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.get(['web-lb', 'http', 'api', '--network', '114']) }
    assert_equal '2 L7 policies are named "api" (IDs pol-1, pol-2). Use the L7 policy\'s ID.', err.message
  end

  ## every new command's help

  def test_every_command_runs_through_handle
    [MtnCloud::Cli::LoadBalancers, MtnCloud::Cli::LoadBalancerListeners, MtnCloud::Cli::LoadBalancerPools,
     MtnCloud::Cli::LoadBalancerMembers, MtnCloud::Cli::LoadBalancerMonitors, MtnCloud::Cli::LoadBalancerL7Policies].each do |klass|
      command, ops = command_for(klass)
      output, result = capture_output { command.handle(['--help']) }
      assert_equal 0, result, klass.to_s
      assert_match(/list\t/, output)
      command, ops = command_for(klass)
      sub_args = klass == MtnCloud::Cli::LoadBalancers ? ['get', 'web-lb'] : ['list', 'web-lb']
      sub_args << 'web' if klass == MtnCloud::Cli::LoadBalancerMembers
      sub_args << 'http' if klass == MtnCloud::Cli::LoadBalancerL7Policies
      capture_output { command.handle(sub_args + ['--network', '114']) }
      assert_equal ['read'], ops.runs.collect(&:first), klass.to_s
    end
  end

  def test_help_names_the_network_option
    [[MtnCloud::Cli::LoadBalancerMembers, :list], [MtnCloud::Cli::LoadBalancerMonitors, :get],
     [MtnCloud::Cli::LoadBalancerL7Policies, :get], [MtnCloud::Cli::LoadBalancerListeners, :get],
     [MtnCloud::Cli::LoadBalancerPools, :list], [MtnCloud::Cli::LoadBalancers, :list]].each do |klass, sub|
      command, ops = command_for(klass)
      output, = capture_output do
        err = assert_raise(SystemExit) { command.send(sub, ['--help']) }
        assert_equal 0, err.status
      end
      assert_match(/--network NETWORK/, output, "#{klass} #{sub}")
      assert_match(/MTN Network name or ID/, output)
      assert_no_match(/--max|--offset|--sort|--query|-Q,/, output)
      assert_empty ops.runs
    end
  end

  def test_a_missing_network_is_reported_before_connecting
    [[MtnCloud::Cli::LoadBalancers, :list, []], [MtnCloud::Cli::LoadBalancers, :get, ['web-lb']],
     [MtnCloud::Cli::LoadBalancers, :floating_ip_options, []], [MtnCloud::Cli::LoadBalancerListeners, :list, ['web-lb']],
     [MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'web']], [MtnCloud::Cli::LoadBalancerMembers, :list, ['web-lb', 'web']],
     [MtnCloud::Cli::LoadBalancerMonitors, :list, ['web-lb']], [MtnCloud::Cli::LoadBalancerL7Policies, :list, ['web-lb', 'http']]].each do |klass, sub, args|
      command = klass.new
      command.define_singleton_method(:lb_connect) {|_o| raise "#{klass} #{sub} connected" }
      err = assert_raise(MtnCloud::Cli::CommandArgumentsError, "#{klass} #{sub}") { command.send(sub, args) }
      assert_match(/--network is required/, err.message)
    end
  end
end
