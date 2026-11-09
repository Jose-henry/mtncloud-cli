require 'mtncloud/cli/cli_command'

# Load balancers on an MTN Network, through the Load Balancer Operations task.
class MtnCloud::Cli::LoadBalancers
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View load balancers on an MTN Network."
  set_command_name :'load-balancers'
  register_subcommands :list, :get, :'floating-ip-options', :add, :update, :remove, :refresh

  # deprecated the `load-balancers types` command in 5.3.2, it moved to `load-balancer-types list`
  register_subcommands :types
  set_subcommands_hidden :types

  set_subcommand_descriptions({
    'list' => "List the load balancers on an MTN Network.",
    'get' => "Show a load balancer with its listeners and pools.",
    'floating-ip-options' => "List the floating IP pools and free floating IPs of an MTN Network.",
    'add' => "Not available yet.",
    'update' => "Not available yet.",
    'remove' => "Not available yet.",
    'refresh' => "Not available.",
  })

  PAGE_SIZE_MAX = MtnCloud::Cli::LoadBalancerOperationsHelper::LB_PAGE_SIZE_MAX

  def connect(options)
    lb_connect(options)
  end

  def list(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--network NETWORK")
      build_lb_network_option(opts, options)
      opts.on('--name NAME', String, "Only load balancers with this exact name.") do |val|
        options[:lb_name] = val
      end
      opts.on('--status STATUS', String, "Only load balancers in this provisioning or operating status, for example ACTIVE or ONLINE (case ignored).") do |val|
        options[:lb_status] = val
      end
      opts.on('--page NUMBER', String, "Show this page of the list, starting at 1.") do |val|
        options[:lb_page] = val
      end
      opts.on('--page-size NUMBER', String, "Load balancers per page, 1 to #{PAGE_SIZE_MAX}. The default is 100 when --page is given.") do |val|
        options[:lb_page_size] = val
      end
      build_standard_get_options(opts, options, [], [:query])
      opts.footer = <<-EOT
List the load balancers on an MTN Network, sorted by name.
#{lb_network_footer}
This is the list the console shows on the network's Load Balancers tab. To see a load balancer's
current state, use `#{prog_name} #{command_name} get`, which reads it live.
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    page = lb_whole_number(options[:lb_page], '--page', 1, nil, optparse)
    page_size = lb_whole_number(options[:lb_page_size], '--page-size', 1, PAGE_SIZE_MAX, optparse)
    connect(options)
    network = lb_network!(options, optparse)
    inputs = {'networkId' => network[:id], 'name' => options[:lb_name], 'status' => options[:lb_status],
              'page' => page, 'pageSize' => page_size}.reject {|_k, v| v.nil? }
    answer = lb_run('list', inputs, network, options)
    return 0, nil if answer.nil?
    output = lb_output(answer)
    if !output['loadbalancers'].is_a?(Array)
      raise lb_error("The load balancer list answered without a list of load balancers. Try again.", :unexpected, 'list')
    end
    rows = output['loadbalancers'] = lb_sort(output['loadbalancers'])
    render_response(output, options, 'loadbalancers') do
      print_h1 "Load Balancers", lb_access_subtitles(output, network), options
      if rows.empty?
        print cyan, (output['total'].to_i > 0 ? "No load balancers on this page." : "No load balancers found on MTN Network #{network[:label]}."), reset, "\n"
      else
        print cyan
        print as_pretty_table(rows, load_balancer_list_columns, options)
        print_lb_page_footer(output, rows)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def get(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("[load balancer] --network NETWORK")
      build_lb_read_options(opts, options)
      opts.footer = <<-EOT
Show a load balancer with its listeners and pools, read live.
[load balancer] is required. This is the ID or the exact name of a load balancer; a name must match only one.
#{lb_network_footer}
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:1)
    connect(options)
    network = lb_network!(options, optparse)
    answer = lb_read(network, args[0], options)
    return 0, nil if answer.nil?
    output = lb_output(answer)
    lb = output['loadbalancer']
    render_response(output, options, 'loadbalancer') do
      print_h1 "Load Balancer Details", lb_access_subtitles(output, network), options
      print cyan
      print_description_list(load_balancer_columns, lb, options)
      listeners = lb_sort(lb['listeners'])
      print_h2 "Listeners", options
      if listeners.empty?
        print cyan, "No listeners.", reset, "\n"
      else
        print cyan, as_pretty_table(listeners, lb_listener_list_columns(lb), options)
      end
      pools = lb_sort(lb['pools'])
      print_h2 "Pools", options
      if pools.empty?
        print cyan, "No pools.", reset, "\n"
      else
        print cyan, as_pretty_table(pools, lb_pool_list_columns, options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def floating_ip_options(args)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = subcommand_usage("--network NETWORK")
      build_lb_read_options(opts, options)
      opts.footer = <<-EOT
List where a load balancer on an MTN Network can get a public IP: the floating IP pools,
and the floating IPs your project holds that are not attached to anything.
#{lb_network_footer}
EOT
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:0)
    connect(options)
    network = lb_network!(options, optparse)
    answer = lb_run('fip-options', {'networkId' => network[:id]}, network, options)
    return 0, nil if answer.nil?
    output = lb_output(answer)
    output['floatingIpPools'] = (output['floatingIpPools'] || []).sort_by {|it| [it['name'].to_s, it['externalId'].to_s] }
    output['availableFloatingIps'] = (output['availableFloatingIps'] || []).sort_by {|it| [it['address'].to_s, it['id'].to_s] }
    render_response(output, options) do
      print_h1 "Floating IP Options", ["MTN Network: #{network[:label]}"], options
      print_h2 "Floating IP Pools", options
      if output['floatingIpPools'].empty?
        print cyan, "No floating IP pools.", reset, "\n"
      else
        print cyan, as_pretty_table(output['floatingIpPools'], {"Name" => 'name', "ID" => 'externalId'}, options)
      end
      print_h2 "Available Floating IPs", options
      if output['availableFloatingIps'].empty?
        print cyan, "No free floating IPs.", reset, "\n"
      else
        print cyan, as_pretty_table(output['availableFloatingIps'], {"ID" => 'id', "Address" => 'address'}, options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  def add(args)
    lb_unavailable(args, 'add', "Creating a load balancer isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def update(args)
    lb_unavailable(args, 'update', "Changing a load balancer isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def remove(args)
    lb_unavailable(args, 'remove', "Deleting a load balancer isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def refresh(args)
    lb_unavailable(args, 'refresh', "Refreshing a load balancer isn't available. `#{prog_name} #{command_name} get` reads a load balancer's live state.")
  end

  # deprecated, to be removed in the future.
  def types(args)
    print_error yellow,"[DEPRECATED] The command `load-balancers types` is deprecated and replaced by `load-balancer-types list`.",reset,"\n"
    my_terminal.execute("load-balancer-types list #{args.join(' ')}")
  end

  protected

  def load_balancer_list_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "VIP" => lambda {|it| it['vip_display'].to_s.empty? ? it['vip_address'] : it['vip_display'] },
      "Floating IP" => lambda {|it| format_lb_known(it['vip_floating'], it['vip_floating_known']) },
      "Members" => lambda {|it| format_lb_known(it['membersCount'], it['membersKnown']) },
    }.merge(lb_status_columns).merge({
      "Created" => lambda {|it| format_lb_time(it['created_at']) },
    })
  end

  def load_balancer_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "VIP Address" => 'vip_address',
      "VIP Subnet" => lambda {|it| it['vip_subnet_display'].to_s.empty? ? it['vip_subnet_id'] : it['vip_subnet_display'] },
      "Provisioning Status" => lambda {|it| format_lb_status(it['provisioning_status']) },
      "Operating Status" => lambda {|it| format_lb_status(it['operating_status']) },
      "Enabled" => lambda {|it| format_boolean(it['admin_state_up']) },
      "Tags" => lambda {|it| format_lb_list(it['tags']) },
      "Created" => lambda {|it| format_lb_time(it['created_at']) },
      "Updated" => lambda {|it| format_lb_time(it['updated_at']) },
    }
  end

  def print_lb_page_footer(output, rows)
    return unless output['page']
    first = (output['page'].to_i - 1) * output['pageSize'].to_i + 1
    print cyan, "Showing #{first}-#{first + rows.size - 1} of #{output['total']}.", reset, "\n"
  end

  # A whole number option between min and max, or nil when not given.
  def lb_whole_number(val, flag, min, max, optparse)
    return nil if val.nil?
    n = Integer(val.to_s, 10) rescue nil
    if n.nil? || n < min || (max && n > max)
      raise_args_error("#{flag} must be a whole number #{max ? "from #{min} to #{max}" : "of at least #{min}"}", [], optparse)
    end
    n
  end

end
