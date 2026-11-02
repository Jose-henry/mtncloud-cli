require 'test/unit'
require 'stringio'
require 'timeout'
require 'tmpdir'
require 'fileutils'
require 'mtncloud'

# Offline branding checks for the MTN Cloud CLI, no appliance needed.
#
# Renders --help for every command and subcommand and fails if any line still
# mentions morpheus (other than approved server-side values), or if any help
# screen raises a Ruby error.
#
#   bundle exec ruby -Ilib -Itest test/branding_test.rb
class BrandingTest < Test::Unit::TestCase

  # Approved keep-list. These are values the appliance or API depends on,
  # or names of external services, so they must not be rebranded.
  ALLOWED = [
    /morph-(cli|api)/,                       # OAuth client IDs
    /X-Morpheus-(Token|Lease)/,              # API headers
    /\$?MORPHEUS_LEASE_TOKEN/,               # set by the appliance
    /morpheus\.(task|workflow|securityScan)/, # job type codes
    /Default is morpheus\./,                 # blueprint type value, marketplace organization
    /Morpheus Hub/,                          # HPE's external service
    /\.morpkg/,                              # package file format
    /morpheus\.yml/,                         # deploy file fallback
  ]

  # Known lines still to be rebranded, keyed by the step that removes them.
  # Remove an entry in the same commit that fixes it, the test fails if an entry no longer appears.
  PENDING = {
  }

  class << self
    attr_reader :screens, :errors

    def startup
      @screens = {}
      @errors = []
      saved_terminal = MtnCloud::Terminal.instance_variable_get(:@morphterm)
      saved_home = MtnCloud::Cli.home_directory
      home = Dir.mktmpdir("mtncloud_branding_test")
      out, err = StringIO.new, StringIO.new
      # commands print through MtnCloud::Terminal.instance, so point a terminal at StringIOs
      MtnCloud::Terminal.new(stdin: StringIO.new(""), stdout: out, stderr: err, homedir: home)
      # include hidden commands, they can still be invoked
      commands = MtnCloud::Cli::CliRegistry.instance.instance_variable_get(:@commands)
      commands.sort_by {|name, _| name.to_s }.each do |name, klass|
        invocations = [["--help"]] + klass.subcommands.keys.map {|sub| [sub.to_s, "--help"] }
        invocations.each do |args|
          label = ([name] + args[0..-2]).join(" ")
          @screens[label] = capture(out, err, label) { klass.new.handle(args.dup) }
        end
      end
    ensure
      MtnCloud::Terminal.instance_variable_set(:@morphterm, saved_terminal)
      MtnCloud::Cli.home_directory = saved_home
      FileUtils.rm_rf(home) if home
    end

    def capture(out, err, label)
      [out, err].each {|io| io.truncate(0); io.rewind }
      old_stdout, old_stderr, old_stdin = $stdout, $stderr, $stdin
      $stdout, $stderr, $stdin = out, err, StringIO.new("")
      begin
        Timeout.timeout(15) { yield }
      rescue SystemExit
        # --help exits after printing
      rescue Timeout::Error
        @errors << "#{label}: timed out"
      rescue NameError, NoMethodError, ArgumentError, TypeError => e
        @errors << "#{label}: #{e.class}: #{e.message.lines.first.strip}"
      rescue StandardError
        # other errors, such as no remote configured, are expected offline
      ensure
        $stdout, $stderr, $stdin = old_stdout, old_stderr, old_stdin
      end
      out.string + err.string
    end
  end

  def morpheus_lines
    lines = []
    self.class.screens.each do |label, text|
      text.each_line do |line|
        line = line.strip
        next unless line =~ /morpheus/i
        next if ALLOWED.any? {|re| line =~ re }
        lines << [label, line]
      end
    end
    lines
  end

  def test_help_screens_were_rendered
    assert_operator self.class.screens.size, :>, 1000, "expected to render help for every command and subcommand"
  end

  def test_help_screens_raise_no_errors
    assert_empty self.class.errors, "help screens raised errors:\n" + self.class.errors.join("\n")
  end

  def test_help_has_no_unapproved_morpheus
    unexpected = morpheus_lines.reject {|_, line| PENDING.keys.any? {|re| line =~ re } }
    assert_empty unexpected, "help text still mentions morpheus:\n" +
      unexpected.map {|label, line| "  #{label}: #{line}" }.join("\n")
  end

  def test_pending_lines_still_exist
    lines = morpheus_lines.map(&:last)
    stale = PENDING.reject {|re, _| lines.any? {|line| line =~ re } }
    assert_empty stale, "these PENDING entries are fixed, remove them from the list:\n" +
      stale.map {|re, step| "  (#{step}) #{re.inspect}" }.join("\n")
  end

  def test_version_banner_is_mtn_cloud
    out = StringIO.new
    saved_terminal = MtnCloud::Terminal.instance_variable_get(:@morphterm)
    saved_home = MtnCloud::Cli.home_directory
    MtnCloud::Terminal.new(stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, homedir: Dir.tmpdir)
    MtnCloud::Cli::VersionCommand.new.handle([])
    assert_include out.string, "MTN Cloud CLI"
    assert_include out.string, "Client Version: #{MtnCloud::Cli::VERSION}"
    # the old banner spelled Morpheus in ASCII art, which a text search cannot see
    assert_not_match(/__  ___/, out.string)
  ensure
    MtnCloud::Terminal.instance_variable_set(:@morphterm, saved_terminal)
    MtnCloud::Cli.home_directory = saved_home
  end

  # update must not make network requests, it only prints the update command
  def test_update_prints_manual_instructions_without_network
    out = StringIO.new
    saved_terminal = MtnCloud::Terminal.instance_variable_get(:@morphterm)
    saved_home = MtnCloud::Cli.home_directory
    MtnCloud::Terminal.new(stdin: StringIO.new(""), stdout: out, stderr: StringIO.new, homedir: Dir.tmpdir)
    HTTP.define_singleton_method(:get) {|*args| raise "update must not make HTTP requests" }
    # -f and -y are ignored but still accepted
    exit_code, err = MtnCloud::Cli::UpdateCommand.new.handle(["-f", "-y"])
    assert_equal 0, exit_code
    assert_include out.string, "Installed version: #{MtnCloud::Cli::VERSION}"
    assert_include out.string, "gem update mtncloud-cli"
  ensure
    HTTP.singleton_class.send(:remove_method, :get) if HTTP.singleton_methods(false).include?(:get)
    MtnCloud::Terminal.instance_variable_set(:@morphterm, saved_terminal)
    MtnCloud::Cli.home_directory = saved_home
  end

  def test_prog_name_follows_invoked_name
    original = $0
    { "/usr/local/bin/mcs" => "mcs", "C:/Ruby33-x64/bin/mcs" => "mcs", "bin/mtncloud" => "mtncloud",
      "rake" => "mtncloud", "/usr/bin/morpheus" => "mtncloud" }.each do |program, expected|
      $0 = program
      assert_equal expected, MtnCloud::Cli.prog_name, "prog_name when invoked as #{program}"
    end
  ensure
    $0 = original
  end
end
