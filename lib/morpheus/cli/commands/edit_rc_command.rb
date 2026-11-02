require 'morpheus/cli/cli_command'

# Command for editing the .mtncloud_profile initalization script
class Morpheus::Cli::EditRcCommand
  include Morpheus::Cli::CliCommand
  set_command_name :'edit-rc'
  #set_command_hidden

  def handle(args)
    options = {}
    editor = nil
    filename = Morpheus::Cli::DotFile.mtncloudrc_filename
    optparse = Morpheus::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: #{prog_name} #{command_name}"
      opts.on( '-e', '--editor PROGRAM', "Editor program to use. The default is $EDITOR." ) do |val|
        editor = val.gsub("'",'')
      end
      build_common_options(opts, options, [])
      opts.footer = <<-EOT
Edit your .mtncloudrc script located in the mtncloud home directory.
This script runs at the beginning of the interactive #{prog_name} shell command.
It provides a way to initialize your interactive #{prog_name} shell environment.

Example:

# customize the mtncloud shell prompt
set-prompt "%cyan%username%reset@%magenta%remote %cyanmtncloud> %reset"

# print the mtncloud cli version
version

# print the current remote appliance version
remote get current

# greetings
echo "Welcome back %username"
EOT
    end
    optparse.parse!(args)
    

    if !editor
      editor = ENV['EDITOR']
    end

    # try something...
    if !editor
      if Morpheus::Cli.windows?
        editor = "notepad"
      else
        editor = "nano"
      end
    end

    if !editor
      print_error Morpheus::Terminal.angry_prompt
      puts_error "You have not defined an EDITOR."
      puts_error "Try export EDITOR=emacs"
      #puts "Trying nano..."
      #editor = "nano"
      return 1
    end
    has_editor = true
    puts "opening #{filename} for editing"
    system(editor, filename)
    if !$?.success?
      print_error Morpheus::Terminal.angry_prompt
      puts_error "edit command failed with #{$?.exitstatus}: #{editor} #{filename}"
      return $?.exitstatus
    end
    if Morpheus::Cli::Shell.has_instance?
      puts "use 'reload' to re-execute your startup script"
    end
    return 0 # $?
  end

end
