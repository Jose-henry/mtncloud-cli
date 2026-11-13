require 'test/unit'
require 'stringio'
require 'mtncloud'

# `mtncloud search --go` does not open a load balancer result: load balancers are read per MTN
# Network, and a search result carries no network, so it answers as for any type it cannot open.
class SearchLoadBalancerTest < Test::Unit::TestCase

  class FakeSearch
    attr_reader :calls

    def initialize(hits)
      @hits = hits
      @calls = []
    end

    def setopts(_options)
      self
    end

    def list(params = {})
      @calls << params
      {'hits' => @hits}
    end
  end

  def build_command(hits)
    search = FakeSearch.new(hits)
    command = MtnCloud::Cli::SearchCommand.new
    command.define_singleton_method(:connect) {|_options| @search_interface = search }
    [command, search]
  end

  def capture_stdout
    terminal = MtnCloud::Terminal.instance
    original = terminal.stdout
    buffer = StringIO.new
    terminal.set_stdout(buffer)
    yield
    buffer.string
  ensure
    terminal.set_stdout(original)
  end

  def test_go_on_a_load_balancer_result_gives_the_unsupported_result_error
    command, search = build_command([{'type' => 'LoadBalancer', 'id' => 7, 'name' => 'web-lb', 'score' => 1.0}])
    original = MtnCloud::Cli::LoadBalancers.instance_method(:handle)
    MtnCloud::Cli::LoadBalancers.send(:define_method, :handle) {|_args| raise "load-balancers must not be invoked" }
    begin
      err = nil
      capture_stdout do
        err = assert_raise(MtnCloud::Cli::CommandError) { command.handle(['web-lb', '--go']) }
      end
      assert_equal "Sorry, result cannot be loaded. type: LoadBalancer, id: 7, name: web-lb", err.message
      assert_equal 1, search.calls.size
    ensure
      MtnCloud::Cli::LoadBalancers.send(:define_method, :handle, original)
    end
  end

  def test_load_balancer_results_have_no_command_and_other_types_keep_theirs
    command, = build_command([])
    assert_nil command.send(:lookup_mtncloud_command, 'LoadBalancer')
    assert_nil command.send(:lookup_mtncloud_command, 'loadbalancer')
    assert_equal MtnCloud::Cli::Clouds, command.send(:lookup_mtncloud_command, 'ComputeZone')
    assert_equal MtnCloud::Cli::NetworksCommand, command.send(:lookup_mtncloud_command, 'Network')
  end
end
