require 'mtncloud/cli/cli_command'

# Command for editing the .mtncloud_profile initialization script
class MtnCloud::Cli::EditProfileCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :'edit-profile'
  #set_command_hidden

  def handle(args)
    options = {}
    editor = ENV['EDITOR'] || 'nano'
    filename = MtnCloud::Cli::DotFile.mtncloud_profile_filename
    optparse = MtnCloud::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: #{prog_name} #{command_name}"
      opts.on( '-e', '--editor PROGRAM', "Editor program to use. The default is $EDITOR." ) do |val|
        editor = val
      end
      build_common_options(opts, options, [])
      opts.footer = <<-EOT
Edit your .mtncloud_profile script located in the mtncloud home directory.
This script runs whenever the #{prog_name} terminal command is executed.
It provides a way to initialize your cli environment for all #{prog_name} commands.

Example:

# disable coloring to exclude ansi characters in output
coloring off -q

# Enable debugging to print extra output for troubleshooting
debug on

EOT
    end
    optparse.parse!(args)

    if !editor
      print_error MtnCloud::Terminal.angry_prompt
      puts_error "You have not defined an EDITOR."
      puts_error "Try export EDITOR=emacs"
      #puts "Trying nano..."
      #editor = "nano"
      return 1
    end
    puts "opening #{filename} for editing"
    system(editor, filename)
    if !$?.success?
      print_error MtnCloud::Terminal.angry_prompt
      puts_error "edit command failed with #{$?.exitstatus}: #{editor} #{filename}"
      return $?.exitstatus
    end
    if MtnCloud::Cli::Shell.has_instance?
      puts "use 'reload' to re-execute your startup script"
    end
    return 0 # $?
  end

end
