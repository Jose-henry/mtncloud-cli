require 'mtncloud/cli/cli_command'

# This is for writing STDIN to files(s)
class MtnCloud::Cli::TeeCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :tee
  set_command_hidden

  def handle(args)
    print_red_alert "#{command_name} is not yet supported"
    return -1
  end

end
