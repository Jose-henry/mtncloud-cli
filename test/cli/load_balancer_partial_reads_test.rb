require 'lb_test_support'

# A read the plugin could only partly finish answers with the unread part marked, not empty. The
# overview commands (load-balancers get, load-balancer-pools get) say which part could not be
# read; a command whose answer depends on that part fails rather than show an empty or partial
# list, in every output format.
class LoadBalancerPartialReadsTest < Test::Unit::TestCase
  include LbTestSupport

  FORMATS = [[], ['-j'], ['-y'], ['--csv']]

  def run_command(klass, sub, args, answer, format = [])
    command, ops = build_lb_command(klass, {'read' => answer})
    output, result = capture_output { command.send(sub, args + ['--network', '114'] + format) }
    assert_equal 1, ops.runs.size
    [output, result]
  end

  def assert_unread(klass, sub, args, answer, message)
    FORMATS.each do |format|
      command, = build_lb_command(klass, {'read' => answer})
      err = assert_raise(MtnCloud::Cli::LoadBalancerError, "#{klass} #{sub} #{format.join}") do
        capture_output { command.send(sub, args + ['--network', '114'] + format) }
      end
      assert_equal :unexpected, err.kind
      assert_equal message, err.message
    end
  end

  ## listeners not read

  def test_get_says_the_listeners_could_not_be_read
    output, result = run_command(MtnCloud::Cli::LoadBalancers, :get, ['web-lb'], partial_read_answer(:listeners))
    assert_equal [0, nil], result
    text = strip_color(output)
    assert_match(/The listeners could not be read: could not list listeners\. Run the command again\./, text)
    assert_no_match(/No listeners\./, text)
    assert_no_match(/lis-80/, text, "ID-only entries are not shown as listeners")
    assert_match(/pool-web/, text, "the pools that were read are still shown")
    assert_nothing_hidden(output)
  end

  def test_get_json_keeps_the_listeners_error
    output, = run_command(MtnCloud::Cli::LoadBalancers, :get, ['web-lb'], partial_read_answer(:listeners), ['-j'])
    lb = JSON.parse(output)['loadbalancer']
    assert_equal 'could not list listeners', lb['listeners_error']
    assert_equal [{'id' => 'lis-443'}, {'id' => 'lis-80'}], lb['listeners']
    assert_nothing_hidden(output)
  end

  def test_listener_and_l7_commands_fail_when_the_listeners_could_not_be_read
    msg = "The load balancer's listeners could not be read: could not list listeners. Run the command again."
    answer = partial_read_answer(:listeners)
    assert_unread(MtnCloud::Cli::LoadBalancerListeners, :list, ['web-lb'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerListeners, :get, ['web-lb', 'lis-80'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerL7Policies, :list, ['web-lb', 'lis-80'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerL7Policies, :get, ['web-lb', 'lis-80', 'pol-1'], answer, msg)
  end

  ## pools not read

  def test_get_says_the_pools_could_not_be_read
    output, result = run_command(MtnCloud::Cli::LoadBalancers, :get, ['web-lb'], partial_read_answer(:pools))
    assert_equal [0, nil], result
    text = strip_color(output)
    assert_match(/The pools could not be read: could not list pools\. Run the command again\./, text)
    assert_no_match(/No pools\./, text)
    assert_match(/lis-80/, text, "the listeners that were read are still shown")
  end

  def test_pool_member_and_monitor_commands_fail_when_the_pools_could_not_be_read
    msg = "The load balancer's pools could not be read: could not list pools. Run the command again."
    answer = partial_read_answer(:pools)
    assert_unread(MtnCloud::Cli::LoadBalancerPools, :list, ['web-lb'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'pool-web'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMembers, :list, ['web-lb', 'pool-web'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMembers, :get, ['web-lb', 'pool-web', 'mem-1'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMonitors, :list, ['web-lb'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMonitors, :get, ['web-lb', 'mon-web'], answer, msg)
  end

  ## a pool's members not read

  def test_members_that_could_not_be_read_are_not_shown_as_none
    msg = "The members of pool web could not be read: List members failed: the load balancer service returned 503. Run the command again."
    answer = partial_read_answer(:members)
    assert_unread(MtnCloud::Cli::LoadBalancerMembers, :list, ['web-lb', 'web'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMembers, :get, ['web-lb', 'web', 'mem-1'], answer, msg)
    output, = run_command(MtnCloud::Cli::LoadBalancerMembers, :list, ['web-lb', 'api'], answer)
    assert_match(/No members\./, strip_color(output), "a pool whose members were read still lists them")
  end

  def test_pool_get_says_its_members_could_not_be_read
    output, = run_command(MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'web'], partial_read_answer(:members))
    text = strip_color(output)
    assert_match(/The members could not be read: List members failed: the load balancer service returned 503\. Run the command again\./, text)
    assert_no_match(/No members\./, text)
    assert_match(/web-check/, text, "the monitor that was read is still shown")
    assert_nothing_hidden(output)
    output, = run_command(MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'web'], partial_read_answer(:members), ['-j'])
    pool = JSON.parse(output)['pool']
    assert !pool.key?('members')
    assert_equal [3, ['mem-2', 'mem-1', 'mem-3']], [pool['member_count'], pool['member_ids']]
    assert_equal 'List members failed: the load balancer service returned 503', pool['members_error']
    assert_nothing_hidden(output)
  end

  def test_pool_tables_count_unread_members_as_not_read
    [[MtnCloud::Cli::LoadBalancerPools, :list, ['web-lb']], [MtnCloud::Cli::LoadBalancers, :get, ['web-lb']]].each do |klass, sub, args|
      output, = run_command(klass, sub, args, partial_read_answer(:members))
      text = strip_color(output)
      assert_match(/\| web\s+\| HTTP\s+\| ROUND_ROBIN\s+\| 3 \(not read\)\s+\|/, text, "#{klass} #{sub}")
    end
    output, = run_command(MtnCloud::Cli::LoadBalancers, :get, ['web-lb'], partial_read_answer(:members))
    assert_match(/The members or health monitors of some pools could not be read\. Run the command again\./, strip_color(output))
  end

  ## a pool's health monitor not read

  def test_monitor_commands_fail_when_a_monitor_could_not_be_read
    msg = "The health monitor of pool web could not be read: Get HealthMonitor failed: timed out. Run the command again."
    answer = partial_read_answer(:monitor)
    assert_unread(MtnCloud::Cli::LoadBalancerMonitors, :list, ['web-lb'], answer, msg)
    assert_unread(MtnCloud::Cli::LoadBalancerMonitors, :get, ['web-lb', 'mon-web'], answer, msg)
  end

  def test_pool_get_and_tables_say_the_monitor_is_unknown
    output, = run_command(MtnCloud::Cli::LoadBalancerPools, :get, ['web-lb', 'web'], partial_read_answer(:monitor))
    text = strip_color(output)
    assert_match(/The health monitor could not be read: Get HealthMonitor failed: timed out\. Run the command again\./, text)
    assert_no_match(/No health monitor\./, text)
    assert_match(/10\.0\.0\.11/, text, "the members that were read are still shown")
    output, = run_command(MtnCloud::Cli::LoadBalancerPools, :list, ['web-lb'], partial_read_answer(:monitor))
    assert_match(/\| web\s+\| HTTP\s+\| ROUND_ROBIN\s+\| 3\s+\| Unknown\s+\|/, strip_color(output))
  end

  ## nothing hidden leaks from a partial read, in any format

  def test_partial_reads_hide_the_plugins_own_fields_in_every_format
    %i[listeners pools members monitor].each do |part|
      FORMATS.each do |format|
        output, = run_command(MtnCloud::Cli::LoadBalancers, :get, ['web-lb'], partial_read_answer(part), format)
        HIDDEN.each {|re| assert_no_match(re, output, "#{part} #{format.join}") }
      end
    end
  end
end
