require 'mtncloud/cli/mixins/print_helper'

# Mixin for the load balancer commands, which run through the Load Balancer Operations task
# (MtnCloud::LoadBalancerOperationsInterface) rather than a REST endpoint.
#
# Every command names its MTN Network with --network. A load balancer is read with the plugin's
# `read` action, which is always live, and its listeners, pools, members, monitors and L7 policies
# all come from that one read: a command reads each load balancer at most once. `list` answers
# from the plugin's stored list and never asks it to refresh, as the Terraform provider does.
#
# What the commands print never carries the plugin's execution details, its freshness details, the
# tags it adds for itself, or the cloud provider's name.
module MtnCloud::Cli::LoadBalancerOperationsHelper

  def self.included(klass)
    klass.send :include, MtnCloud::Cli::PrintHelper
  end

  # Fields of the result itself rather than of a load balancer: the route's own success flag and
  # how fresh a stored list is. Only the top level of the result is checked, so a resource keeps
  # every field of its own (an L7 policy's action, say).
  LB_RESULT_HIDDEN_FIELDS = %w[success fresh stale ageMs source]
  # The cloud provider behind a load balancer, on a list row and on a read load balancer.
  LB_LOAD_BALANCER_HIDDEN_FIELDS = %w[provider]
  # Fields kept for the plugin's or the cloud's own use, removed at every depth: the cloud project
  # (project_id, tenant_id), how a member was added (it is in the member's tags too), and the
  # plugin's status diagnostics.
  LB_PLUGIN_FIELDS = %w[project_id tenant_id morpheus_origin health_checked health_error] # mtncloud:allow-upstream-name (plugin member field removed from output)
  # Tags the plugin adds for itself: its request tag, and every tag in its own namespace (the
  # instance, external, group and group-weight markers on members).
  LB_REQUEST_TAG_PREFIX = 'mtncloud-req-'
  LB_PLUGIN_TAG_PREFIX = 'morpheus:' # mtncloud:allow-upstream-name (prefix of the plugin's own tags, removed from output)
  LB_UUID = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/
  LB_PAGE_SIZE_MAX = 500

  # Connects and sets up the interfaces the load balancer commands use.
  def lb_connect(options)
    @api_client = establish_remote_appliance_connection(options)
    @load_balancer_operations_interface = @api_client.load_balancer_operations
    @networks_interface = @api_client.networks
    @lb_reads = {}
  end

  def load_balancer_operations_interface
    raise "#{self.class} has not defined @load_balancer_operations_interface" if @load_balancer_operations_interface.nil?
    @load_balancer_operations_interface
  end

  def build_lb_network_option(opts, options)
    opts.on('--network NETWORK', String, "MTN Network name or ID. Required.") do |val|
      options[:network] = val
    end
  end

  # The standard options of a load balancer read: no paging or sorting of the generic kind, which
  # the plugin does not offer.
  def build_lb_read_options(opts, options)
    build_lb_network_option(opts, options)
    build_lb_output_options(opts, options)
  end

  # Output and connection options. No -Q: the plugin takes no query parameters.
  def build_lb_output_options(opts, options)
    build_common_options(opts, options, [:json, :yaml, :csv, :fields, :select, :delim, :quiet, :dry_run, :remote])
  end

  # --network is checked before connecting, so a missing one is reported as such.
  def lb_require_network!(options, optparse=nil)
    if options[:network].to_s.strip.empty?
      raise_args_error("--network is required", [], optparse)
    end
  end

  def lb_network_footer
    "--network is required. This is the name or ID of the MTN Network the load balancer is on."
  end

  # The network as {id:, label:}. An ID is sent as it is, as the Terraform provider does; a name is
  # looked up, and must match exactly one MTN Network, owned or shared with your tenant.
  def lb_network!(options, optparse=nil)
    val = options[:network].to_s.strip
    if val.empty?
      raise_args_error("--network is required", [], optparse)
    end
    if val =~ /\A\d+\z/
      return {id: val, label: val}
    end
    if options[:dry_run]
      # a dry run sends nothing, not even the network lookup, so the request it shows names the
      # network as unresolved rather than with a made-up ID
      return {id: "<unresolved network name: #{val}>", label: val}
    end
    networks = (@networks_interface.list({name: val})['networks'] || []).select {|it| it['name'] == val }
    if networks.empty?
      raise lb_error("MTN Network \"#{val}\" was not found.", :not_found)
    elsif networks.size > 1
      ids = networks.collect {|it| it['id'] }.join(', ')
      raise lb_error("#{networks.size} MTN Networks are named \"#{val}\" (IDs #{ids}). Use the network's ID.", :not_found)
    end
    {id: networks[0]['id'].to_s, label: val}
  end

  # How the plugin is told which load balancer: a UUID is its ID, anything else its exact name.
  def lb_selector(val)
    val.to_s =~ LB_UUID ? {'lbId' => val.to_s} : {'name' => val.to_s}
  end

  # Runs one action. Returns the plugin's answer, or nil after printing the request in a dry run.
  def lb_run(action, inputs, network, options)
    load_balancer_operations_interface.setopts(options)
    answer = begin
      load_balancer_operations_interface.run(action, inputs)
    rescue MtnCloud::Cli::LoadBalancerError => e
      raise lb_customer_error(e, network)
    end
    if options[:dry_run]
      print_dry_run(answer, options)
      return nil
    end
    answer
  end

  # One load balancer, read once per command. Returns the answer, or nil in a dry run.
  def lb_read(network, lb, options)
    @lb_reads ||= {}
    key = "#{network[:id]}|#{lb}"
    return @lb_reads[key] if @lb_reads.key?(key)
    answer = lb_run('read', {'networkId' => network[:id]}.merge(lb_selector(lb)), network, options)
    return nil if answer.nil?
    loadbalancer = answer['result'].is_a?(Hash) ? answer['result']['loadbalancer'] : nil
    if !loadbalancer.is_a?(Hash)
      raise lb_error("The load balancer read answered without a load balancer. Try again.", :unexpected, 'read')
    end
    @lb_reads[key] = answer
  end

  # The answer's result made fit to show. The run's details (success, action, caller,
  # permissionSource) are in the answer around the result and never copied. From the result go its
  # own success and freshness fields, the load balancers' provider, the plugin's and the cloud's
  # own fields, and the plugin's own tags. networkAccess (owner or shared) comes from the answer
  # around the result.
  def lb_output(answer)
    result = answer['result'].is_a?(Hash) ? answer['result'] : {}
    out = lb_clean(result.reject {|k, _v| LB_RESULT_HIDDEN_FIELDS.include?(k.to_s) })
    if out['loadbalancers'].is_a?(Array)
      out['loadbalancers'] = out['loadbalancers'].collect {|row| lb_without(row, LB_LOAD_BALANCER_HIDDEN_FIELDS) }
    end
    if out['loadbalancer'].is_a?(Hash)
      out['loadbalancer'] = lb_without(out['loadbalancer'], LB_LOAD_BALANCER_HIDDEN_FIELDS)
    end
    out['networkAccess'] = answer['networkAccess'] if answer.key?('networkAccess')
    out
  end

  # At every depth: removes the plugin's and the cloud's own fields and the plugin's own tags, and
  # says a part's read error (listeners_error, members_error...) in MTN Cloud terms. Every other
  # field is kept as it is.
  def lb_clean(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), out|
        key = k.to_s
        next if LB_PLUGIN_FIELDS.include?(key)
        out[k] = if key == 'tags' && v.is_a?(Array)
          lb_user_tags(v)
        elsif key.end_with?('_error') && v.is_a?(String)
          lb_text(v)
        else
          lb_clean(v)
        end
      end
    when Array
      obj.collect {|it| lb_clean(it) }
    else
      obj
    end
  end

  def lb_without(obj, keys)
    obj.is_a?(Hash) ? obj.reject {|k, _v| keys.include?(k.to_s) } : obj
  end

  def lb_user_tags(tags)
    tags.reject {|t| t.to_s.start_with?(LB_REQUEST_TAG_PREFIX) || t.to_s.start_with?(LB_PLUGIN_TAG_PREFIX) }
  end

  # Picks one piece by ID, else by exact name. None, or several with that name, is an error.
  def lb_pick(items, val, what)
    items = items || []
    found = items.select {|it| it['id'].to_s == val.to_s }
    found = items.select {|it| !it['name'].to_s.empty? && it['name'].to_s == val.to_s } if found.empty?
    if found.empty?
      raise lb_error("The load balancer has no #{what} with the ID or name \"#{val}\". Names are matched exactly.", :not_found)
    elsif found.size > 1
      ids = found.collect {|it| it['id'] }.join(', ')
      whats = what.end_with?('y') ? "#{what[0..-2]}ies" : "#{what}s"
      raise lb_error("#{found.size} #{whats} are named \"#{val}\" (IDs #{ids}). Use the #{what}'s ID.", :not_found)
    end
    found[0]
  end

  ## parts the plugin could not read
  #
  # A read the plugin could only partly finish still answers, with the unread part marked rather
  # than empty: listeners_error or pools_error (the listeners or pools are then only their IDs),
  # members_error on a pool (members absent), healthmonitor_error on a pool (monitor absent),
  # l7policies_error on a listener and rules_error on an L7 policy. A command whose answer depends
  # on such a part is an error, never an empty list.

  def lb_unread_error(what, why)
    lb_error("The #{what} could not be read: #{lb_text(why)}. Run the command again.", :unexpected, 'read')
  end

  # The load balancer's listeners, or an error when they could not be read.
  def lb_listeners!(loadbalancer)
    raise lb_unread_error("load balancer's listeners", loadbalancer['listeners_error']) unless loadbalancer['listeners_error'].to_s.empty?
    loadbalancer['listeners'] || []
  end

  # The load balancer's pools, or an error when they could not be read.
  def lb_pools!(loadbalancer)
    raise lb_unread_error("load balancer's pools", loadbalancer['pools_error']) unless loadbalancer['pools_error'].to_s.empty?
    loadbalancer['pools'] || []
  end

  # A pool's members, or an error when they could not be read.
  def lb_pool_members!(pool)
    raise lb_unread_error("members of pool #{lb_label(pool)}", pool['members_error']) unless pool['members_error'].to_s.empty?
    pool['members'] || []
  end

  def lb_label(item)
    item['name'].to_s.empty? ? item['id'].to_s : item['name'].to_s
  end

  # The health monitors of a load balancer: each pool's monitor, with that pool's ID and name. A
  # monitor that could not be read is an error: listing the rest would hide it.
  def lb_monitors(loadbalancer)
    out = []
    lb_pools!(loadbalancer).each do |pool|
      raise lb_unread_error("health monitor of pool #{lb_label(pool)}", pool['healthmonitor_error']) unless pool['healthmonitor_error'].to_s.empty?
      m = pool['healthmonitor']
      next unless m.is_a?(Hash) && !m['id'].to_s.empty?
      out << m.merge('pool_id' => pool['id'], 'pool_name' => pool['name'])
    end
    lb_sort(out, 'pool_name')
  end

  # In an overview (load-balancers get, pool get): a section that could not be read says so.
  def lb_print_unread(title, why, options)
    print_h2 title, options
    print yellow, "The #{title.downcase} could not be read: #{lb_text(why)}. Run the command again.", reset, "\n"
  end

  # A listener's L7 policies. When they or their rules could not be read, that is an error, never
  # an empty list.
  def lb_l7_policies(listener)
    if !listener['l7policies_error'].to_s.empty?
      raise lb_error("The listener's L7 policies could not be read: #{lb_text(listener['l7policies_error'])}. Run the command again.", :unexpected, 'read')
    end
    policies = listener['l7policies_expanded'] || []
    policies.each do |p|
      if !p['rules_error'].to_s.empty?
        raise lb_error("The rules of L7 policy #{p['id']} could not be read: #{lb_text(p['rules_error'])}. Run the command again.", :unexpected, 'read')
      end
    end
    policies.sort_by {|p| [p['position'].to_i, p['name'].to_s, p['id'].to_s] }
  end

  def lb_sort(items, field='name')
    (items || []).sort_by {|it| [it[field].to_s, it['id'].to_s] }
  end

  ## the commands about a load balancer's pieces

  def lb_piece_footer
    "[load balancer] is required. This is the ID or the exact name of a load balancer; a name must match only one.\n" +
    lb_network_footer
  end

  # Parses a piece command's options and arguments, connects and names the network.
  # Returns [options, network], or raises.
  def lb_piece_parse(args, banner, count, footer)
    options = {}
    optparse = MtnCloud::Cli::OptionParser.new do |opts|
      opts.banner = banner
      build_lb_read_options(opts, options)
      opts.footer = footer
    end
    optparse.parse!(args)
    verify_args!(args:args, optparse:optparse, count:count)
    lb_require_network!(options, optparse)
    connect(options)
    [options, lb_network!(options, optparse)]
  end

  # The load balancer read for a piece command, cleaned for output: [output, loadbalancer], or nil
  # in a dry run.
  def lb_piece_read(network, lb, options)
    answer = lb_read(network, lb, options)
    return nil if answer.nil?
    output = lb_output(answer)
    [output, output['loadbalancer']]
  end

  def lb_piece_subtitles(output, network)
    lb = output['loadbalancer'] || {}
    ["Load Balancer: #{lb['name'].to_s.empty? ? lb['id'] : lb['name']}"] + lb_access_subtitles(output, network)
  end

  # CSV takes its columns from the first row, so a field only some rows have (an instance-backed
  # member's instanceId, say) would be lost. For CSV, every row gets every row's fields, null where
  # it has none (the CLI writes null as null). Other formats are left as they are.
  def lb_csv_rows(items, options)
    return items unless options[:csv] && items.is_a?(Array)
    keys = []
    items.each {|it| it.keys.each {|k| keys << k unless keys.include?(k) } if it.is_a?(Hash) }
    items.collect {|it| it.is_a?(Hash) ? keys.each_with_object({}) {|k, row| row[k] = it[k] } : it }
  end

  # Prints a list of pieces, or renders it as {key => items}.
  def lb_render_list(key, items, title, columns, output, network, options, empty_text)
    render_response({key => lb_csv_rows(items, options)}, options, key) do
      print_h1 title, lb_piece_subtitles(output, network), options
      if items.empty?
        print cyan, empty_text, reset, "\n"
      else
        print cyan, as_pretty_table(items, columns, options)
      end
      print reset, "\n"
    end
    return 0, nil
  end

  # Prints one piece, or renders it as {key => item}. The block prints any sections after it.
  def lb_render_one(key, item, title, columns, output, network, options)
    render_response({key => item}, options, key) do
      print_h1 title, lb_piece_subtitles(output, network), options
      print cyan
      print_description_list(columns, item, options)
      yield if block_given?
      print reset, "\n"
    end
    return 0, nil
  end

  def lb_print_section(title, items, columns, options, empty_text)
    print_h2 title, options
    if items.nil? || items.empty?
      print cyan, empty_text, reset, "\n"
    else
      print cyan, as_pretty_table(items, columns, options)
    end
  end

  def lb_enabled_columns
    {
      "Enabled" => lambda {|it| format_boolean(it['admin_state_up']) },
      "Provisioning Status" => lambda {|it| format_lb_status(it['provisioning_status']) },
      "Operating Status" => lambda {|it| format_lb_status(it['operating_status']) },
      "Tags" => lambda {|it| format_lb_list(it['tags']) },
    }
  end

  # A subcommand that is not available yet: it says so and sends nothing.
  def lb_unavailable(args, subcommand, message)
    if args.include?('-h') || args.include?('--help')
      print "Usage: #{prog_name} #{command_name} #{subcommand}\n\n"
      print "Not available yet. #{message}\n"
      return 0, nil
    end
    raise lb_error(message, :unavailable)
  end

  def lb_error(msg, kind, action=nil, details={})
    MtnCloud::Cli::LoadBalancerError.new(msg, kind: kind, action: action, details: details)
  end

  def lb_text(msg)
    MtnCloud::LoadBalancerOperationsInterface.customer_text(msg)
  end

  ## display

  def lb_access_subtitles(output, network)
    subtitles = ["MTN Network: #{network[:label]}"]
    subtitles << "Read only (shared MTN Network)" if output['canManage'] == false
    subtitles
  end

  def format_lb_status(status, return_color=cyan)
    s = status.to_s
    color = case s.upcase
      when 'ACTIVE', 'ONLINE' then green
      when 'ERROR', 'OFFLINE' then red
      when /\APENDING/, 'DEGRADED' then yellow
      else cyan
    end
    s.empty? ? '' : "#{color}#{s}#{return_color}"
  end

  def format_lb_time(value)
    value.to_s.empty? ? '' : format_local_dt(value)
  rescue StandardError
    value.to_s
  end

  def format_lb_known(value, known)
    known == false ? 'Unknown' : value.to_s
  end

  def format_lb_list(values, empty='')
    values.is_a?(Array) && !values.empty? ? values.join(', ') : empty
  end

  def format_lb_pool_ref(loadbalancer, pool_id)
    return '' if pool_id.to_s.empty?
    pool = (loadbalancer['pools'] || []).find {|p| p['id'] == pool_id }
    pool && !pool['name'].to_s.empty? ? "#{pool['name']} (#{pool_id})" : pool_id.to_s
  end

  def format_lb_session_persistence(sp)
    return '' unless sp.is_a?(Hash) && !sp['type'].to_s.empty?
    sp['cookie_name'].to_s.empty? ? sp['type'].to_s : "#{sp['type']} (#{sp['cookie_name']})"
  end

  def lb_status_columns
    {
      "Provisioning" => lambda {|it| format_lb_status(it['provisioning_status']) },
      "Operating" => lambda {|it| format_lb_status(it['operating_status']) },
    }
  end

  def lb_listener_list_columns(loadbalancer)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Protocol" => 'protocol',
      "Port" => 'protocol_port',
      "Default Pool" => lambda {|it| format_lb_pool_ref(loadbalancer, it['default_pool_id']) },
      "TLS" => lambda {|it| format_boolean(!it['default_tls_container_ref'].to_s.empty?) },
    }.merge(lb_status_columns)
  end

  def lb_pool_list_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Protocol" => 'protocol',
      "Algorithm" => 'lb_algorithm',
      "Members" => lambda {|it| format_lb_member_count(it) },
      "Monitor" => lambda {|it| format_lb_pool_monitor(it) },
    }.merge(lb_status_columns)
  end

  # A pool's member count. Members that could not be read are not none: the count of their IDs is
  # shown when the plugin has it, marked as not read, else Unknown.
  def format_lb_member_count(pool)
    return pool['members'].size if pool['members'].is_a?(Array)
    return "#{pool['member_count']} (not read)" if !pool['members_error'].to_s.empty? && pool['member_count']
    'Unknown'
  end

  def format_lb_pool_monitor(pool)
    return 'Unknown' unless pool['healthmonitor_error'].to_s.empty?
    pool['healthmonitor'].is_a?(Hash) ? (pool['healthmonitor']['type'] || 'Yes') : ''
  end

  # Whether some pools' members or monitors could not be read, for a note under a pools table.
  def lb_pools_partly_unread?(pools)
    (pools || []).any? {|p| !p['members_error'].to_s.empty? || !p['healthmonitor_error'].to_s.empty? }
  end

  def lb_member_list_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Address" => 'address',
      "Port" => 'protocol_port',
      "Weight" => 'weight',
      "Backup" => lambda {|it| format_boolean(it['backup']) },
    }.merge(lb_status_columns)
  end

  private

  # A refusal said in MTN Cloud terms, keeping the plugin's words where they help.
  def lb_customer_error(e, network)
    return e unless e.kind == :refused
    msg = e.message.to_s
    m = msg.downcase
    if m.include?("is not available to your tenant")
      return lb_error("MTN Network #{network[:label]} is not available to your tenant.", :refused, e.action,
                      e.details.merge(plugin_message: msg))
    end
    if lb_missing_message?(m)
      hint = "`#{prog_name} load-balancers list --network #{network[:label]}` lists the network's load balancers."
      return lb_error("#{msg.sub(/\.?\s*\z/, '.')} #{hint}", :not_found, e.action, e.details)
    end
    e
  end

  # The plugin's answers that mean "no such load balancer here", by the Terraform provider's rules.
  def lb_missing_message?(m)
    gone = !m.include?("on this network") && (m.include?("not found in this project") || m.include?("could not be found") ||
      m.include?("404") || (m.include?("load balancer") && m.include?("not found")))
    gone || m.include?("was not found on this network") || m.include?("no load balancer named") ||
      (m.include?("load balancers") && m.include?("are named"))
  end

end
