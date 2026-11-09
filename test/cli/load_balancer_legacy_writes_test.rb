require 'lb_test_support'

# The REST load balancer commands that remain (virtual servers, pool nodes, profiles) keep their
# reads, but their writes say they are not available and send nothing: that endpoint holds no
# load balancers on MTN Cloud.
class LoadBalancerLegacyWritesTest < Test::Unit::TestCase
  include LbTestSupport

  COMMANDS = {
    MtnCloud::Cli::LoadBalancerVirtualServers => [/virtual server isn't available in the CLI yet/, /load-balancer-listeners` shows/],
    MtnCloud::Cli::LoadBalancerPoolNodes => [/pool node isn't available in the CLI yet/, /load-balancer-members` shows/],
    MtnCloud::Cli::LoadBalancerProfiles => [/load balancer profile isn't available in the CLI\./, /MTN Cloud console/],
  }

  def test_writes_say_they_are_not_available_and_send_nothing
    COMMANDS.each do |klass, patterns|
      %w[add update remove].each do |sub|
        command = klass.new
        command.define_singleton_method(:connect) {|_o| raise "#{klass} #{sub} connected" }
        command.define_singleton_method(:establish_remote_appliance_connection) {|_o| raise "#{klass} #{sub} connected" }
        err = assert_raise(MtnCloud::Cli::LoadBalancerError, "#{klass} #{sub}") { command.send(sub, ['lb-1', 'x', '-d']) }
        assert_equal :unavailable, err.kind
        patterns.each {|re| assert_match re, err.message, "#{klass} #{sub}" }
      end
    end
  end

  def test_help_says_not_available_yet
    COMMANDS.each_key do |klass|
      command = klass.new
      usage = command.full_command_usage
      %w[add update remove].each {|sub| assert_match(/\t#{sub}\tNot available yet\./, usage, "#{klass} #{sub}") }
      %w[list get].each {|sub| assert_match(/\t#{sub}\b/, usage) }
      output, result = capture_output { command.add(['--help']) }
      assert_equal [0, nil], result
      assert_match(/Not available yet\./, output)
    end
  end

  def test_reads_are_unchanged
    COMMANDS.each_key do |klass|
      %i[list get].each do |sub|
        owner = klass.instance_method(sub).owner
        assert_include [MtnCloud::Cli::RestCommand, MtnCloud::Cli::SecondaryRestCommand], owner, "#{klass} #{sub} comes from the REST mixins"
      end
    end
  end
end
