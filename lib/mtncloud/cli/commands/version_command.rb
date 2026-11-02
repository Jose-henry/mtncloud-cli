# a command for printing this client version
require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::VersionCommand
  include MtnCloud::Cli::CliCommand

  set_command_name :version
  def initialize
  end

  def usage
    "#{prog_name} version"
  end

  def handle(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = usage
      opts.on('-v','--short', "Print only the client version number") do |val|
        options[:short] = true
      end
      build_common_options(opts, options)
    end
    optparse.parse!(args)

    client_version = MtnCloud::Cli::VERSION
    if options[:short]
      puts client_version
    else
      print cyan
      puts("****************************************")
      puts("  MTN Cloud CLI")
      puts("  Client Version: #{client_version}")
      puts("****************************************")
      print reset
    end
  end
end
