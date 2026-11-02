require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::Logout
  include MtnCloud::Cli::CliCommand

  def connect(options)
    @api_client = establish_remote_appliance_connection(options.merge({:no_prompt => true, :skip_verify_access_token => true, :skip_login => true}))
  end

  def usage
    "Usage: #{prog_name} logout"
  end

  def handle(args)
    logout(args)
  end

  def logout(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = usage
      build_common_options(opts, options, [:remote, :quiet])
      opts.footer = <<-EOT
Logout of a remote appliance.
This clears your credentials so that you will need to login again.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args,count:0,optpare:optparse)
    connect(options)

    if !@appliance_name
      print_error MtnCloud::Terminal.angry_prompt
      puts_error "Please specify an MTN Cloud appliance to logout of with -r or see the command `remote use`"
      return 1
    end
    wallet = MtnCloud::Cli::Credentials.new(@appliance_name, @appliance_url).load_saved_credentials
    token = wallet ? wallet['access_token'] : nil
    if !token
      if !options[:quiet]
        puts "You are not currently logged in to #{display_appliance(@appliance_name, @appliance_url)}"
      end
    else
      # todo: need to tell the server to delete the token too..
      # delete token from credentials file
      # note: this also handles updating appliance session info
      MtnCloud::Cli::Credentials.new(@appliance_name, @appliance_url).logout()
      if !options[:quiet]
        puts "#{cyan}Logged out of #{@appliance_name}. Goodbye #{wallet['username']}!#{reset}"
      end
    end
    # recalcuate echo vars
    MtnCloud::Cli::Echo.recalculate_variable_map()
    # recalculate shell prompt after this change
    if MtnCloud::Cli::Shell.has_instance?
      MtnCloud::Cli::Shell.instance.reinitialize()
    end
    return 0

  end


end
