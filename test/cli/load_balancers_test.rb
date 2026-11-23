require 'lb_test_support'

# Unit tests for `mtncloud load-balancers`: list, get and floating-ip-options run through the
# Load Balancer Operations task; add, update, remove and refresh are not available yet.
class LoadBalancersCommandTest < Test::Unit::TestCase
  include LbTestSupport

  def command_with(answers = {}, networks = [{'id' => 114, 'name' => 'app-net'}])
    build_lb_command(MtnCloud::Cli::LoadBalancers, answers, networks: networks)
  end

  ## list

  def test_list_sends_only_the_network_and_never_refresh
    command, ops = command_with('list' => list_answer)
    output, = capture_output { command.list(['--network', '114']) }
    assert_equal [['list', {'networkId' => '114'}]], ops.runs
    text = strip_color(output)
    assert_match(/Load Balancers/, text)
    assert_match(/MTN Network: 114/, text)
    assert_operator text.index('web-lb'), :<, text.index('api-lb'), "the plugin's order: oldest first"
    assert_match(/198\.51\.100\.7/, text)
    assert_match(/Unknown/, text)
    assert_no_match(/Read only/, text)
    assert_nothing_hidden(output)
  end

  def test_list_keeps_the_plugins_order_in_every_format
    rows = [list_row('id' => 'c', 'name' => 'zeta', 'created_at' => '2026-10-01T00:00:00'),
            list_row('id' => 'a', 'name' => 'alpha', 'created_at' => '2026-10-02T00:00:00'),
            list_row('id' => 'b', 'name' => 'mid', 'created_at' => '2026-10-03T00:00:00')]
    output, = capture_output { command_with('list' => list_answer(rows))[0].list(['--network', '114', '-j']) }
    assert_equal ['c', 'a', 'b'], JSON.parse(output)['loadbalancers'].collect {|r| r['id'] }
    output, = capture_output { command_with('list' => list_answer(rows))[0].list(['--network', '114', '--csv']) }
    assert_equal ['c', 'a', 'b'], output.strip.lines[1..].collect {|l| l.split(',').first }
    output, = capture_output { command_with('list' => list_answer(rows))[0].list(['--network', '114']) }
    text = strip_color(output)
    assert_operator text.index('zeta'), :<, text.index('alpha')
    assert_operator text.index('alpha'), :<, text.index('mid')
  end

  def test_list_vip_column_is_the_vip_address
    output, = capture_output { command_with('list' => list_answer)[0].list(['--network', '114']) }
    text = strip_color(output)
    assert_match(/\| web-lb \| 10\.0\.0\.5\s+\| 198\.51\.100\.7\s+\|/, text)
    assert_no_match(%r{10\.0\.0\.5/198}, text, "the VIP column does not repeat the floating IP")
    output, = capture_output { command_with('list' => list_answer)[0].list(['--network', '114', '-j']) }
    assert_equal '10.0.0.5/198.51.100.7', JSON.parse(output)['loadbalancers'][0]['vip_display'], "JSON keeps the field"
  end

  def test_a_live_list_says_when_member_counts_could_not_be_checked
    output, = capture_output do
      command_with('list' => list_answer(nil, {'partial' => true, 'unresolvedCount' => 1}))[0].list(['--network', '114'])
    end
    assert_match(/The members of 1 load balancer could not be counted\./, strip_color(output))
    output, = capture_output { command_with('list' => list_answer)[0].list(['--network', '114']) }
    assert_no_match(/could not be counted/, strip_color(output))
  end

  def test_get_shows_the_load_balancers_problems
    output, = capture_output { command_with('read' => read_answer)[0].get(['web-lb', '--network', '114']) }
    text = strip_color(output)
    assert_match(/Problems/, text)
    assert_match(/member\s+\| 10\.0\.0\.11:8080 \| web\s+\| ACTIVE\s+\| ERROR/, text)
    output, = capture_output { command_with('read' => read_answer({'health_problems' => []}))[0].get(['web-lb', '--network', '114']) }
    assert_no_match(/Problems/, strip_color(output))
  end

  def test_floating_ip_options_help_says_only_the_owner_may
    command, = command_with
    output, = capture_output do
      err = assert_raise(SystemExit) { command.floating_ip_options(['--help']) }
      assert_equal 0, err.status
    end
    assert_match(/Only the network's owner may attach floating IPs/, output)
    assert_match(/floating-ip-options\tList the floating IP pools and free floating IPs of an MTN Network you own\./, command.full_command_usage)
  end

  def test_list_filters_and_paging_are_sent_as_strings_by_the_interface
    command, ops = command_with('list' => list_answer(nil, {'page' => 2, 'pageSize' => 2, 'total' => 5}))
    output, = capture_output do
      command.list(['--network', 'app-net', '--name', 'web-lb', '--status', 'active', '--page', '2', '--page-size', '2'])
    end
    assert_equal [['list', {'networkId' => '114', 'name' => 'web-lb', 'status' => 'active', 'page' => 2, 'pageSize' => 2}]], ops.runs
    assert_match(/Showing 3-4 of 5\./, strip_color(output))
  end

  def test_list_checks_paging_before_sending_anything
    [['--page', '0'], ['--page', 'x'], ['--page-size', '0'], ['--page-size', '501'], ['--page-size', '1.5']].each do |flag, val|
      command, ops = command_with('list' => list_answer)
      err = assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.list(['--network', '114', flag, val]) }
      assert_match(/#{flag} must be a whole number/, err.message)
      assert_empty ops.runs
    end
  end

  def test_list_requires_the_network
    command, ops = command_with('list' => list_answer)
    err = assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.list([]) }
    assert_match(/--network is required/, err.message)
    assert_empty ops.runs
  end

  def test_list_json_keeps_resource_fields_and_drops_the_rest
    command, = command_with('list' => list_answer(nil, network_access: 'shared', can_manage: false))
    output, = capture_output { command.list(['--network', '114', '--json']) }
    json = JSON.parse(output)
    assert_equal %w[loadbalancers total canManage networkAccess], json.keys
    assert_equal 'shared', json['networkAccess']
    assert_equal false, json['canManage']
    assert_equal list_row.keys - ['provider'], json['loadbalancers'][1].keys
    assert_nothing_hidden(output)
  end

  def test_list_yaml_and_csv_drop_the_hidden_fields
    %w[--yaml --csv].each do |flag|
      command, = command_with('list' => list_answer)
      output, = capture_output { command.list(['--network', '114', flag]) }
      assert_match(/web-lb/, output)
      assert_match(/membersCount/, output)
      assert_nothing_hidden(output)
    end
  end

  def test_list_on_a_shared_network_says_read_only
    command, = command_with('list' => list_answer(nil, network_access: 'shared', can_manage: false))
    output, = capture_output { command.list(['--network', '114']) }
    assert_match(/Read only \(shared MTN Network\)/, strip_color(output))
  end

  def test_empty_list
    command, = command_with('list' => list_answer([]))
    output, = capture_output { command.list(['--network', 'app-net']) }
    assert_match(/No load balancers found on MTN Network app-net\./, strip_color(output))
  end

  def test_a_list_answer_without_a_list_is_an_error
    command, = command_with('list' => {'success' => true, 'result' => {'total' => 0}})
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { capture_output { command.list(['--network', '114']) } }
    assert_equal :unexpected, err.kind
  end

  def test_list_dry_run_prints_the_request_and_sends_nothing_else
    command, ops, nets = command_with('list' => list_answer)
    output, = capture_output { command.list(['--network', 'app-net', '-d']) }
    assert_match(%r{/api/tasks/\{lboperate\.terraform\}/execute}, output)
    assert_equal [['list', {'networkId' => '<unresolved network name: app-net>'}]], ops.runs
    assert_empty nets.list_calls
    assert_equal true, ops.setopts_calls.last[:dry_run]
  end

  ## get

  def test_get_by_name_and_by_id
    command, ops = command_with('read' => read_answer)
    output, = capture_output { command.get(['web-lb', '--network', '114']) }
    command2, ops2 = command_with('read' => read_answer)
    capture_output { command2.get([LB_ID, '--network', '114']) }
    assert_equal [['read', {'networkId' => '114', 'name' => 'web-lb'}]], ops.runs
    assert_equal [['read', {'networkId' => '114', 'lbId' => LB_ID}]], ops2.runs
    text = strip_color(output)
    %w[Listeners Pools front\ door app-subnet https TERMINATED_HTTPS ROUND_ROBIN prod].each {|s| assert_include text, s }
    assert_include text, 'web (pool-web)'
    assert_nothing_hidden(output)
  end

  def test_get_json_is_the_whole_load_balancer
    command, = command_with('read' => read_answer)
    output, = capture_output { command.get(['web-lb', '--network', '114', '-j']) }
    json = JSON.parse(output)
    assert_equal %w[loadbalancer canManage networkAccess], json.keys
    assert_equal visible_load_balancer.keys, json['loadbalancer'].keys
    assert_equal CERT_REF, json['loadbalancer']['listeners'][0]['default_tls_container_ref']
    assert_nothing_hidden(output)
  end

  def test_no_format_shows_what_the_plugin_keeps_for_itself
    commands = [[MtnCloud::Cli::LoadBalancers, :get, ['web-lb']], [MtnCloud::Cli::LoadBalancers, :list, []],
                [MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'web']], [MtnCloud::Cli::LoadBalancerMembers, :list, ['web-lb', 'web']],
                [MtnCloud::Cli::LoadBalancerMembers, :get, ['web-lb', 'web', 'mem-3']], [MtnCloud::Cli::LoadBalancerListeners, :list, ['web-lb']]]
    commands.each do |klass, sub, args|
      [[], ['-j'], ['-y'], ['--csv']].each do |format|
        command, = build_lb_command(klass, {'read' => read_answer, 'list' => list_answer})
        output, = capture_output { command.send(sub, args + ['--network', '114'] + format) }
        assert_not_empty output, "#{klass} #{sub} #{format}"
        HIDDEN.each {|re| assert_no_match(re, output, "#{klass} #{sub} #{format.join}") }
      end
    end
  end

  def test_get_json_yaml_and_csv_keep_the_load_balancers_own_fields
    output, = capture_output { command_with('read' => read_answer)[0].get(['web-lb', '--network', '114', '-y']) }
    %w[flavor_id availability_zone health_problems vip_subnet_display].each {|k| assert_match(/^  #{k}:/, output) }
    output, = capture_output { command_with('read' => read_answer)[0].get(['web-lb', '--network', '114', '--csv']) }
    assert_equal visible_load_balancer.keys.join(','), output.lines.first.strip
  end

  def test_get_needs_one_load_balancer
    command, ops = command_with('read' => read_answer)
    assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.get(['--network', '114']) }
    assert_empty ops.runs
  end

  ## floating-ip-options

  def test_floating_ip_options
    command, ops = command_with('fip-options' => fip_answer)
    output, = capture_output { command.floating_ip_options(['--network', '114']) }
    assert_equal [['fip-options', {'networkId' => '114'}]], ops.runs
    text = strip_color(output)
    assert_operator text.index('public-a'), :<, text.index('public-b')
    assert_operator text.index('198.51.100.8'), :<, text.index('198.51.100.9')
    output, = capture_output { command_with('fip-options' => fip_answer)[0].floating_ip_options(['--network', '114', '-j']) }
    assert_equal %w[floatingIpPools availableFloatingIps networkAccess], JSON.parse(output).keys
  end

  ## not available yet

  def test_writes_are_not_available_and_send_nothing
    {add: /Creating a load balancer isn't available in the CLI yet/, update: /Changing a load balancer/,
     remove: /Deleting a load balancer/, refresh: /load-balancers get` reads a load balancer's live state/}.each do |sub, msg|
      command, ops, nets = command_with('read' => read_answer)
      err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.send(sub, ['web-lb', '--network', '114', '-d']) }
      assert_equal :unavailable, err.kind
      assert_match msg, err.message
      assert_empty ops.runs
      assert_empty nets.list_calls
    end
  end

  def test_unavailable_help_says_so
    command, = command_with
    output, result = capture_output { command.add(['--help']) }
    assert_equal [0, nil], result
    assert_match(/Usage: mtncloud load-balancers add/, output)
    assert_match(/Not available yet\./, output)
  end

  def test_help_lists_the_subcommands
    command, = command_with
    usage = command.full_command_usage
    %w[list get floating-ip-options add update remove refresh].each {|s| assert_match(/^\t#{s}\t/, usage) }
    assert_match(/add\tNot available yet\./, usage)
    assert_no_match(/\ttypes\t/, usage)
  end
end
