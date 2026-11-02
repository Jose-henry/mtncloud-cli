require 'mtncloud/cli/cli_command'

# This is for use in dotfile scripts
# It allows you to turn colors on or off globally
class MtnCloud::Cli::DebugCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :debug
  set_command_hidden

  def handle(args)
    append_newline = true
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: #{prog_name} #{command_name} [on|off]"
      #build_common_options(opts, options, [])
      opts.on('-q','--quiet', "No Output, do not print to stdout") do
        options[:quiet] = true
      end
      opts.on('-h', '--help', "Print this help" ) do
        puts opts
        exit
      end
      opts.footer = "Enable [on] or Disable [off] debugging for all output.\n" + 
                    "Use [on?] or [off?] to print the current value and exit accordingly." + "\n" +
                    "Passing no arguments is the same as `#{command_name} on`"
    end
    optparse.parse!(args)
    if args.count > 1
      raise_command_error "wrong number of arguments, expected 0-1 and got (#{args.count}) #{args.join(' ')}\n#{optparse}"
    end
    
    debug_was_enabled = MtnCloud::Logging.debug?
    exit_code = 0

    if args.count == 0
      # just print
      # no way, debug means turn it on.
      MtnCloud::Logging.set_log_level(MtnCloud::Logging::Logger::DEBUG)
      ::RestClient.log = MtnCloud::Logging.debug? ? MtnCloud::Logging::DarkPrinter.instance : nil
    else
      subcmd = args[0].to_s.strip
      if subcmd == "on"
        MtnCloud::Logging.set_log_level(MtnCloud::Logging::Logger::DEBUG)
        ::RestClient.log = MtnCloud::Logging.debug? ? MtnCloud::Logging::DarkPrinter.instance : nil
      elsif subcmd == "off"
        MtnCloud::Logging.set_log_level(MtnCloud::Logging::Logger::INFO)
        ::RestClient.log = MtnCloud::Logging.debug? ? MtnCloud::Logging::DarkPrinter.instance : nil
      elsif subcmd == "on?"
        exit_code = MtnCloud::Logging.debug? ? 0 : 1
      elsif subcmd == "off?"
        exit_code = MtnCloud::Logging.debug? ? 1 : 0
      elsif subcmd == "status"
        # just print current value
      else
        puts optparse
        return 127
      end
    end
    unless options[:quiet]
      if MtnCloud::Logging.debug?
        if debug_was_enabled == false
          MtnCloud::Logging::DarkPrinter.puts "debug enabled" if MtnCloud::Logging.debug?
        end
        puts "#{cyan}debug: #{green}on#{reset}"
      else
        if debug_was_enabled == true
          MtnCloud::Logging::DarkPrinter.puts "debug disabled" if MtnCloud::Logging.debug?
        end
        puts "#{cyan}debug: #{dark}off#{reset}"
      end
    end
    return exit_code
  end

end
