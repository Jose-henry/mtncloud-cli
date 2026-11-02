require 'mtncloud/cli/cli_command'

# This is for deleting files and directories!
class MtnCloud::Cli::RemoveFileCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :rm
  set_command_hidden

  def handle(args)
    print_red_alert "#{command_name} is not yet supported"
    return -1
  end

end
