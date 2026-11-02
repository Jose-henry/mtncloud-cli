require 'morpheus/cli/cli_command'

# This is for use in dotfile scripts and the shell..
# mtncloud-cli is not published to RubyGems, so this does not query RubyGems
# or run `gem update`. It prints the installed version and how to update
# manually from the repository.
class Morpheus::Cli::UpdateCommand
  include Morpheus::Cli::CliCommand
  set_command_name :update

  def handle(args)
    options = {}
    optparse = Morpheus::Cli::OptionParser.new do|opts|
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
                    "Updates are not installed automatically, they must be installed manually from the repository."
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)

    unless options[:quiet]
      print cyan, "Installed version: #{Morpheus::Cli::VERSION}", reset, "\n\n"
      print update_instructions
    end
    return 0, nil
  end

  protected

  def update_instructions
    <<-EOT
Updates are not installed automatically.
To update, build and install the latest version from the repository:

    git clone https://github.com/Jose-henry/mtncloud-cli
    cd mtncloud-cli
    gem build mtncloud-cli.gemspec -o mtncloud-cli.gem
    gem install ./mtncloud-cli.gem

If you already have a clone, run `git pull` in it instead of `git clone`.
EOT
  end

end
