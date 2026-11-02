require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::GetPromptCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :'get-prompt'
  set_command_hidden

  def handle(args)
    use_echo = false
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: #{prog_name} #{command_name}"
      build_common_options(opts, options, [])
      opts.on('-e', '--echo', "Use echo to display the prompt, displaying ansi colors and variables." ) do
        use_echo = true
      end
      opts.footer = <<-EOT
Display the current #{prog_name} shell prompt value.
This value can be set using `set-prompt [shell-prompt]`.
EOT
    end
    optparse.parse!(args)
    if args.count != 0
      print_error MtnCloud::Terminal.angry_prompt
      puts_error  "wrong number of arguments, expected 0 and got (#{args.count}) #{args.inspect}\n#{optparse}"
      return 1
    end
    if use_echo
      my_terminal.execute("echo #{my_terminal.prompt}")
    else
      puts self.my_terminal.prompt
    end
    return 0
  end

end
