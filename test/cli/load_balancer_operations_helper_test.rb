require 'lb_test_support'

# Unit tests for MtnCloud::Cli::LoadBalancerOperationsHelper: how a command names the network and
# the load balancer, reads it once, picks its pieces, and cleans the plugin's answer for output.
class LoadBalancerOperationsHelperTest < Test::Unit::TestCase
  include LbTestSupport

  class HelperCommand
    include MtnCloud::Cli::CliCommand
    include MtnCloud::Cli::LoadBalancerOperationsHelper
  end

  def setup
    @command, @ops, @nets = build_lb_command(HelperCommand, {'read' => read_answer},
      networks: [{'id' => 114, 'name' => 'app-net'}, {'id' => 120, 'name' => 'twin'}, {'id' => 121, 'name' => 'twin'}])
    @command.send(:lb_connect, {})
  end

  ## the network

  def test_numeric_network_is_sent_as_it_is_without_a_lookup
    assert_equal({id: '114', label: '114'}, @command.lb_network!({network: '114'}))
    assert_empty @nets.list_calls
  end

  def test_network_name_is_looked_up_and_must_match_exactly
    assert_equal({id: '114', label: 'app-net'}, @command.lb_network!({network: 'app-net'}))
    assert_equal [{name: 'app-net'}], @nets.list_calls
  end

  def test_unknown_network_name
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_network!({network: 'nope'}) }
    assert_equal :not_found, err.kind
    assert_equal 'MTN Network "nope" was not found.', err.message
  end

  def test_network_name_matching_several_lists_their_ids
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_network!({network: 'twin'}) }
    assert_equal '2 MTN Networks are named "twin" (IDs 120, 121). Use the network\'s ID.', err.message
  end

  def test_network_is_required
    err = assert_raise(MtnCloud::Cli::CommandArgumentsError) { @command.lb_network!({}) }
    assert_match(/--network is required/, err.message)
  end

  def test_dry_run_does_not_look_up_a_network_name
    network = @command.lb_network!({network: 'app-net', dry_run: true})
    assert_equal '{MTN Network app-net}', network[:id]
    assert_empty @nets.list_calls
  end

  ## the load balancer

  def test_uuid_is_an_id_and_anything_else_a_name
    assert_equal({'lbId' => LB_ID}, @command.lb_selector(LB_ID))
    assert_equal({'lbId' => LB_ID.upcase}, @command.lb_selector(LB_ID.upcase))
    assert_equal({'name' => 'web-lb'}, @command.lb_selector('web-lb'))
    assert_equal({'name' => '42'}, @command.lb_selector('42'))
  end

  def test_a_load_balancer_is_read_once_per_command
    network = {id: '114', label: '114'}
    first = @command.lb_read(network, 'web-lb', {})
    second = @command.lb_read(network, 'web-lb', {})
    assert_same first, second
    assert_equal [['read', {'networkId' => '114', 'name' => 'web-lb'}]], @ops.runs
  end

  def test_a_read_without_a_load_balancer_is_an_error
    command, = build_lb_command(HelperCommand, {'read' => {'success' => true, 'result' => {'canManage' => true}}})
    command.send(:lb_connect, {})
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.lb_read({id: '1', label: '1'}, 'x', {}) }
    assert_equal :unexpected, err.kind
  end

  ## errors in MTN Cloud terms

  def test_network_not_available_is_said_in_mtn_cloud_terms
    command, = build_lb_command(HelperCommand, {'read' => refused('Network 114 is not available to your tenant')})
    command.send(:lb_connect, {})
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.lb_read({id: '114', label: 'app-net'}, 'x', {}) }
    assert_equal 'MTN Network app-net is not available to your tenant.', err.message
    assert_equal 'Network 114 is not available to your tenant', err.details[:plugin_message]
  end

  def test_missing_load_balancer_points_to_the_list
    ['No load balancer named "x" on this network', 'Load balancer abc was not found on this network',
     'Load balancer abc could not be found', '2 load balancers are named "x" (abc, def): use lbId'].each do |msg|
      command, = build_lb_command(HelperCommand, {'read' => refused(msg)})
      command.send(:lb_connect, {})
      err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.lb_read({id: '114', label: 'app-net'}, 'x', {}) }
      assert_equal :not_found, err.kind, msg
      assert_match(/load-balancers list --network app-net` lists the network's load balancers\.\z/, err.message)
    end
  end

  def test_other_refusals_keep_the_plugins_words
    command, = build_lb_command(HelperCommand, {'read' => refused('The cloud is busy, try later')})
    command.send(:lb_connect, {})
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.lb_read({id: '114', label: '114'}, 'x', {}) }
    assert_equal :refused, err.kind
    assert_equal 'The cloud is busy, try later', err.message
  end

  def test_access_errors_pass_through
    access = MtnCloud::Cli::LoadBalancerError.new('no access', kind: :access)
    command, = build_lb_command(HelperCommand, {'read' => access})
    command.send(:lb_connect, {})
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.lb_read({id: '1', label: '1'}, 'x', {}) }
    assert_same access, err
  end

  ## picking pieces

  def test_pick_by_id_then_by_exact_name
    items = [{'id' => 'a', 'name' => 'web'}, {'id' => 'b', 'name' => 'a'}]
    assert_equal 'a', @command.lb_pick(items, 'a', 'pool')['id']
    assert_equal 'a', @command.lb_pick(items, 'web', 'pool')['id']
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_pick(items, 'Web', 'pool') }
    assert_equal 'The load balancer has no pool with the ID or name "Web". Names are matched exactly.', err.message
  end

  def test_pick_with_several_names_lists_their_ids
    items = [{'id' => 'a', 'name' => 'web'}, {'id' => 'b', 'name' => 'web'}]
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_pick(items, 'web', 'pool') }
    assert_equal '2 pools are named "web" (IDs a, b). Use the pool\'s ID.', err.message
  end

  def test_empty_names_never_match
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_pick([{'id' => 'a', 'name' => ''}], '', 'member') }
    assert_equal :not_found, err.kind
  end

  def test_monitors_come_from_the_pools
    monitors = @command.lb_monitors(read_answer['result']['loadbalancer'])
    assert_equal ['mon-web'], monitors.collect {|m| m['id'] }
    assert_equal 'pool-web', monitors[0]['pool_id']
    assert_equal 'web', monitors[0]['pool_name']
  end

  def test_l7_policies_sorted_by_position
    assert_equal ['pol-1', 'pol-2'], @command.lb_l7_policies(listener_http).collect {|p| p['id'] }
  end

  def test_l7_policies_that_could_not_be_read_are_an_error
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_l7_policies(listener_http.merge('l7policies_error' => 'timeout')) }
    assert_equal "The listener's L7 policies could not be read: timeout. Run the command again.", err.message
    listener = listener_http
    listener['l7policies_expanded'][0]['rules_error'] = 'timeout'
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_l7_policies(listener) }
    assert_equal "The rules of L7 policy pol-2 could not be read: timeout. Run the command again.", err.message
  end

  ## output

  def test_output_drops_run_details_freshness_provider_and_plugin_tags
    out = @command.lb_output(list_answer)
    assert_equal %w[loadbalancers total canManage networkAccess], out.keys
    assert_equal 'owner', out['networkAccess']
    out['loadbalancers'].each {|row| assert !row.key?('provider') }
    assert_equal list_row.keys - ['provider'], out['loadbalancers'][1].keys
    assert_nothing_hidden(JSON.generate(out))
  end

  def test_output_keeps_every_resource_field_and_user_tags
    out = @command.lb_output(read_answer)
    lb = out['loadbalancer']
    assert_equal ['prod'], lb['tags']
    assert_equal read_answer['result']['loadbalancer'].keys, lb.keys
    member_tags = lb['pools'][0]['members'].collect {|m| m['tags'] }
    assert_equal [[], ['blue']], member_tags
    assert_equal ['team-web'], lb['listeners'][1]['tags']
    assert_equal CERT_REF, lb['listeners'][0]['default_tls_container_ref']
    assert_equal [SNI_REF], lb['listeners'][0]['sni_container_refs']
    assert_equal true, out['canManage']
    assert_nothing_hidden(JSON.generate(out))
  end

  ## not available yet

  def test_unavailable_sends_nothing_and_says_so
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { @command.lb_unavailable(['x', '-d'], 'add', 'Not here yet.') }
    assert_equal :unavailable, err.kind
    assert_equal 'Not here yet.', err.message
    assert_empty @ops.runs
  end
end
