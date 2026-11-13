require 'lb_test_support'

# Unit tests for `mtncloud load-balancer-listeners` and `mtncloud load-balancer-pools`: every
# command is one `read` of the load balancer, and the piece is picked from it.
class LoadBalancerListenersPoolsTest < Test::Unit::TestCase
  include LbTestSupport

  def listeners(answer = read_answer)
    build_lb_command(MtnCloud::Cli::LoadBalancerListeners, {'read' => answer}, networks: [{'id' => 114, 'name' => 'app-net'}])
  end

  def pools(answer = read_answer)
    build_lb_command(MtnCloud::Cli::LoadBalancerPools, {'read' => answer}, networks: [{'id' => 114, 'name' => 'app-net'}])
  end

  ## listeners

  def test_listeners_list_is_one_read
    command, ops = listeners
    output, = capture_output { command.list(['web-lb', '--network', 'app-net']) }
    assert_equal [['read', {'networkId' => '114', 'name' => 'web-lb'}]], ops.runs
    text = strip_color(output)
    assert_match(/Load Balancer: web-lb/, text)
    assert_match(/MTN Network: app-net/, text)
    assert_operator text.index('lis-80'), :<, text.index('lis-443'), "sorted by name"
    assert_nothing_hidden(output)
  end

  def test_listeners_list_json
    command, = listeners
    output, = capture_output { command.list([LB_ID, '--network', '114', '-j']) }
    json = JSON.parse(output)
    assert_equal ['listeners'], json.keys
    assert_equal ['lis-80', 'lis-443'], json['listeners'].collect {|l| l['id'] }
    assert_equal ['team-web'], json['listeners'][0]['tags']
    assert_equal listener_http.keys, json['listeners'][0].keys
    assert_nothing_hidden(output)
  end

  def test_listener_get_shows_certificate_references_verbatim
    command, ops = listeners
    output, = capture_output { command.get(['web-lb', 'https', '--network', '114']) }
    assert_equal 1, ops.runs.size
    text = strip_color(output)
    assert_include text, CERT_REF
    assert_include text, SNI_REF
    assert_include text, '203.0.113.0/24'
    assert_match(/Connection Limit: 1000/, text)
    output, = capture_output { listeners[0].get(['web-lb', 'lis-443', '--network', '114', '-j']) }
    json = JSON.parse(output)['listener']
    assert_equal CERT_REF, json['default_tls_container_ref']
    assert_equal [SNI_REF], json['sni_container_refs']
  end

  def test_listener_get_lists_its_l7_policies
    output, = capture_output { listeners[0].get(['web-lb', 'http', '--network', '114']) }
    text = strip_color(output)
    assert_match(/Connection Limit: Unlimited/, text)
    assert_match(/Allowed CIDRs: Any/, text)
    assert_match(/L7 Policies/, text)
    assert_operator text.index('pol-1'), :<, text.index('pol-2'), "sorted by position"
    assert_nothing_hidden(output)
  end

  def test_listener_get_says_when_l7_policies_could_not_be_read
    answer = read_answer
    answer['result']['loadbalancer']['listeners'][1]['l7policies_error'] = 'timed out'
    output, = capture_output { listeners(answer)[0].get(['web-lb', 'http', '--network', '114']) }
    assert_match(/The L7 policies could not be read: timed out\. Run the command again\./, strip_color(output))
  end

  def test_unknown_listener
    command, = listeners
    err = assert_raise(MtnCloud::Cli::LoadBalancerError) { capture_output { command.get(['web-lb', 'ftp', '--network', '114']) } }
    assert_equal 'The load balancer has no listener with the ID or name "ftp". Names are matched exactly.', err.message
  end

  def test_listener_commands_need_their_arguments
    command, ops = listeners
    assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.list(['--network', '114']) }
    assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.get(['web-lb', '--network', '114']) }
    assert_raise(MtnCloud::Cli::CommandArgumentsError) { command.get(['web-lb', 'http']) }
    assert_empty ops.runs
  end

  def test_listener_dry_run_sends_nothing
    command, ops, nets = listeners
    output, = capture_output { command.list(['web-lb', '--network', 'app-net', '-d']) }
    assert_match(/DRY RUN/, output)
    assert_match(/action=read/, output)
    assert_empty nets.list_calls
    assert_equal true, ops.setopts_calls.last[:dry_run]
  end

  ## pools

  def test_pools_list
    command, ops = pools
    output, = capture_output { command.list(['web-lb', '--network', '114']) }
    assert_equal [['read', {'networkId' => '114', 'name' => 'web-lb'}]], ops.runs
    text = strip_color(output)
    assert_operator text.index('pool-api'), :<, text.index('pool-web')
    assert_match(/LEAST_CONNECTIONS/, text)
  end

  def test_pool_get_with_members_and_monitor
    command, = pools
    output, = capture_output { command.get(['web-lb', 'web', '--network', '114']) }
    text = strip_color(output)
    assert_match(/Session Persistence: APP_COOKIE \(sid\)/, text)
    assert_operator text.index('10.0.0.11'), :<, text.index('10.0.0.12'), "members sorted by address"
    assert_match(/web-check/, text)
    assert_nothing_hidden(output)
  end

  def test_pool_get_json_keeps_members_without_plugin_tags
    output, = capture_output { pools[0].get(['web-lb', 'pool-web', '--network', '114', '--json']) }
    pool = JSON.parse(output)['pool']
    assert_equal pool_web.keys, pool.keys
    assert_equal [[], ['blue']], pool['members'].collect {|m| m['tags'] }
    assert_equal 'mon-web', pool['healthmonitor']['id']
    assert_nothing_hidden(output)
  end

  def test_pool_without_monitor
    output, = capture_output { pools[0].get(['web-lb', 'api', '--network', '114']) }
    text = strip_color(output)
    assert_match(/No members\./, text)
    assert_match(/No health monitor\./, text)
  end

  def test_pool_writes_are_not_available
    {add: /Adding a pool isn't available/, update: /Changing a pool/, remove: /Deleting a pool/}.each do |sub, msg|
      command, ops, nets = pools
      err = assert_raise(MtnCloud::Cli::LoadBalancerError) { command.send(sub, ['web-lb', 'web', '--network', '114']) }
      assert_equal :unavailable, err.kind
      assert_match msg, err.message
      assert_empty ops.runs
      assert_empty nets.list_calls
    end
  end
end
