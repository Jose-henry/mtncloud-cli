require 'mtncloud/cli/cli_command'

# This is for use in dotfile scripts and the shell..
# It does not run `gem update` itself. It prints the installed version and
# the command that updates mtncloud-cli from RubyGems.
class MtnCloud::Cli::UpdateCommand
  include MtnCloud::Cli::CliCommand
  set_command_name :update

  def handle(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do|opts|
      opts.banner = "Usage: #{prog_name} #{command_name}"
      # -f and -y no longer do anything, they are still accepted so existing scripts keep working
      opts.on( '-f', '--force', "Ignored, kept for compatibility." ) do
      end
      opts.on( '-y', '--yes', "Ignored, kept for compatibility." ) do
      end
      opts.add_hidden_option('-f, --force')
      opts.add_hidden_option('-y, --yes')
      build_common_options(opts, options, [:dry_run, :quiet])
      opts.footer = "Print the installed version and how to update #{prog_name}.\n" +
                    "Updates are not installed automatically. Run the printed command to update."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)

    unless options[:quiet]
      print cyan, "Installed version: #{MtnCloud::Cli::VERSION}", reset, "\n\n"
      print update_instructions
    end
    return 0, nil
  end

  protected

  def update_instructions
    <<-EOT
Updates are not installed automatically.
To update to the latest version from RubyGems, run:

    gem update mtncloud-cli
EOT
  end

end
