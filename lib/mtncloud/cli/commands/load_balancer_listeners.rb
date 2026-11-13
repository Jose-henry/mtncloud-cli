require 'mtncloud/cli/cli_command'

# The listeners of a load balancer: the ports it receives traffic on.
class MtnCloud::Cli::LoadBalancerListeners
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View the listeners of a load balancer: the ports it receives traffic on."
  set_command_name :'load-balancer-listeners'
  register_subcommands :list, :get

  set_subcommand_descriptions({
    'list' => "List a load balancer's listeners.",
    'get' => "Show one listener, with its certificate references and L7 policies.",
  })

  def connect(options)
    lb_connect(options)
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] --network NETWORK"), 1, <<-EOT)
List a load balancer's listeners, sorted by name.
#{lb_piece_footer}
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    lb_render_list('listeners', lb_sort(lb['listeners']), "Listeners", lb_listener_list_columns(lb), output, network, options,
                   "No listeners.")
  end

  def get(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [listener] --network NETWORK"), 2, <<-EOT)
Show one listener of a load balancer.
#{lb_piece_footer}
[listener] is required. This is the ID or the exact name of the listener.
A TERMINATED_HTTPS listener names its certificate by reference: the reference of a
certificate uploaded in the MTN Cloud console, as the listener form shows it.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    listener = lb_pick(lb['listeners'], args[1], 'listener')
    lb_render_one('listener', listener, "Listener Details", listener_columns(lb), output, network, options) do
      if !listener['l7policies_error'].to_s.empty?
        print_h2 "L7 Policies", options
        print yellow, "The L7 policies could not be read: #{lb_text(listener['l7policies_error'])}. Run the command again.", reset, "\n"
      elsif !(listener['l7policies_expanded'] || []).empty?
        lb_print_section("L7 Policies", lb_l7_policies(listener), l7_policy_list_columns(lb), options, "No L7 policies.")
      end
    end
  end

  protected

  def listener_columns(lb)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Protocol" => 'protocol',
      "Port" => 'protocol_port',
      "Connection Limit" => lambda {|it| it['connection_limit'].to_s == '-1' ? 'Unlimited' : it['connection_limit'].to_s },
      "Default Pool" => lambda {|it| format_lb_pool_ref(lb, it['default_pool_id']) },
      "TLS Certificate" => lambda {|it| it['default_tls_container_ref'].to_s },
      "SNI Certificates" => lambda {|it| format_lb_list(it['sni_container_refs']) },
      "Allowed CIDRs" => lambda {|it| format_lb_list(it['allowed_cidrs'], 'Any') },
      "Client Data Timeout (ms)" => 'timeout_client_data',
      "Member Connect Timeout (ms)" => 'timeout_member_connect',
      "Member Data Timeout (ms)" => 'timeout_member_data',
      "TCP Inspect Timeout (ms)" => 'timeout_tcp_inspect',
    }.merge(lb_enabled_columns)
  end

  def l7_policy_list_columns(lb)
    {
      "Position" => 'position',
      "ID" => 'id',
      "Name" => 'name',
      "Action" => 'action',
      "Rules" => lambda {|it| (it['rules_expanded'] || []).size },
    }.merge(lb_status_columns)
  end

end
