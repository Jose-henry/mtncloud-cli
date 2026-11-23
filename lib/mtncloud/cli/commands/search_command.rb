require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::SearchCommand
  include MtnCloud::Cli::CliCommand
  
  set_command_name :search
  set_command_description "Global search for finding all types of objects"

  def connect(opts)
    @api_client = establish_remote_appliance_connection(opts)
    @search_interface = @api_client.search
  end

  def handle(args)
    options = {}
    params = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = "Usage: #{prog_name} #{command_name} [phrase]"
      opts.on("-g", "--go", "Go get details for the top search result instead of printing the list.") do
        options[:go] = true
      end
      build_standard_list_options(opts, options)
      opts.footer = <<-EOT
Global search for finding all types of objects
[phrase] is required. This is the phrase to search for.
Prints the list of search results with the most relevant first.
or use the --go option to get details about the top result instead.
EOT
    end
    optparse.parse!(args)
    connect(options)
    # verify_args!(args:args, optparse:optparse, min:1)
    if args.count > 0
      options[:phrase] = args.join(" ")
    end
    if options[:phrase].to_s.empty?
      raise_command_error "[phrase] is required.", args, optparse
    end
    params.merge!(parse_list_options(options))
    @search_interface.setopts(options)
    if options[:dry_run]
      print_dry_run @search_interface.dry.list(params)
      return
    end
    json_response = @search_interface.list(params)
    search_results = json_response["hits"] || json_response["results"] || []
    top_result = search_results[0]
    if options[:go]
      if top_result
        print cyan,"Loading top search result: #{format_mtncloud_type(top_result['type'])} #{top_result['name'] || top_result['id']} (score: #{top_result['score']})",reset,"\n"
        return go_to_search_result(top_result, options)
      else
        # print cyan,"No results found.",reset,"\n"
        raise_command_error "No search results for phrase '#{options[:phrase]}'"
      end
    end
    render_response(json_response, options, "hits") do
      print_h1 "Search", parse_list_subtitles(options), options
      if search_results.empty?
        print cyan,"No results found.",reset,"\n"
      else
        columns = {
          "Type" => lambda {|it| format_mtncloud_type(it['type']) },
          "ID" => 'id',
          # "UUID" => 'uuid',
          "Name" => 'name',
          "Decription" => 'description',
          #"Score" => 'score',
          "Date Created" => lambda {|it| format_local_dt(it['dateCreated']) },
        }
        print as_pretty_table(search_results, columns.upcase_keys!, options)
        print_results_pagination(json_response)
      end
      print reset,"\n"
    end
    if search_results.empty?
      return 1, "no results found"
    else
      return 0, nil
    end
  end

  protected

  def format_mtncloud_type(val)
    if val == "ComputeSite"
      "Group"
    elsif val == "ComputeZone"
      "Cloud"
    elsif val == "ComputeServer"
      "Host"
    elsif val == "ComputeServerGroup"
      "Cluster"
    elsif val == "ComputeZonePool"
      "Pool"
    else
      val
    end
  end
  
  def go_to_search_result(result, options)
    result_type = result['type']
    cmd_class = lookup_mtncloud_command(result['type'])
    if cmd_class
      get_options = []
      get_options += (options[:remote] ? ["-r",options[:remote]] : [])
      get_options += (options[:json] ? ["--json"] : [])
      get_options += (options[:yaml] ? ["--yaml"] : [])
      return cmd_class.new.handle(["get", result['id']] + get_options)
    else
      raise_command_error "Sorry, result cannot be loaded. type: #{result_type}, id: #{result['id']}, name: #{result['name']}"
    end
  end


  def lookup_mtncloud_command(result_type)
    case result_type.to_s.downcase
    when "computezone","cloud","zone"
      MtnCloud::Cli::Clouds
    when "computesite","group"
      MtnCloud::Cli::Groups
    when "computeserver","server","host"
      MtnCloud::Cli::Hosts
    when "computeservergroup","serverGroup","cluster"
      MtnCloud::Cli::Clusters
    when "instance"
      MtnCloud::Cli::Instances
    when "app"
      MtnCloud::Cli::Apps
    when "container"
      MtnCloud::Cli::Containers
    when "computezonefolder","zonefolder","resourcefolder"
      # crap, need result.zoneId, or resource-folders should not require cloud actually, get by id
      # MtnCloud::Cli::CloudFoldersCommand
      nil
    when "computezonepool","zonepool","resourcepool"
      # crap, need result.zoneId, or resource-pools should not require cloud actually, get by id
      # MtnCloud::Cli::CloudResourcePoolsCommand
      nil
    # when "chassis"
    #   MtnCloud::Cli::ChassisCommand
    when "network"
      MtnCloud::Cli::NetworksCommand
    when "networkgroup"
      MtnCloud::Cli::NetworkGroupsCommand
    when "networkpool"
      MtnCloud::Cli::NetworkPoolsCommand
    when "networkdomain"
      MtnCloud::Cli::NetworkDomainsCommand
    when "virtualimage"
      MtnCloud::Cli::VirtualImages
    # a "loadbalancer" result is not opened: load balancers are read per MTN Network with
    # `load-balancers get --network`, and a search result carries no network
    # when "virtualserver","loadbalancerinstance"
    #   MtnCloud::Cli::LoadBalancerInstances
    when "instancetype"
      # MtnCloud::Cli::LibraryInstanceTypesCommand
      MtnCloud::Cli::LibraryInstanceTypes
    when "instancetypelayout","layout"
      MtnCloud::Cli::LibraryLayoutsCommand
    when "certificate"
      # todo: WHAT! didnt I write certs already!?
      MtnCloud::Cli::CertificatesCommand
    when "keypair"
      MtnCloud::Cli::KeyPairs
    when "integration"
      MtnCloud::Cli::IntegrationsCommand
    when "account","tenant"
      MtnCloud::Cli::TenantsCommand
    when "user"
      MtnCloud::Cli::Users
    when "role"
      MtnCloud::Cli::Roles
    when "wikipage","wiki"
      MtnCloud::Cli::WikiCommand
    when "clients"
      MtnCloud::Cli::ClientsCommand
    else
      nil
    end
  end

end

