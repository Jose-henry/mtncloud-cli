require 'mtncloud/cli/cli_command'

# The L7 policies of a load balancer listener: rules that redirect or reject HTTP requests.
class MtnCloud::Cli::LoadBalancerL7Policies
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View the L7 policies of a load balancer listener: rules that redirect or reject HTTP requests."
  set_command_name :'load-balancer-l7-policies'
  register_subcommands :list, :get

  set_subcommand_descriptions({
    'list' => "List a listener's L7 policies.",
    'get' => "Show one L7 policy with its rules.",
  })

  def connect(options)
    lb_connect(options)
  end

  def list(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [listener] --network NETWORK"), 2, <<-EOT)
List a listener's L7 policies, in the order they are applied.
#{lb_piece_footer}
[listener] is required. This is the ID or the exact name of the listener.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    listener = lb_pick(lb['listeners'], args[1], 'listener')
    policies = lb_l7_policies(listener)
    lb_render_list('l7policies', policies, "L7 Policies of Listener #{listener['name'].to_s.empty? ? listener['id'] : listener['name']}",
                   policy_list_columns(lb), output, network, options, "No L7 policies.")
  end

  def get(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [listener] [policy] --network NETWORK"), 3, <<-EOT)
Show one L7 policy of a listener, with its rules.
#{lb_piece_footer}
[listener] is required. This is the ID or the exact name of the listener.
[policy] is required. This is the ID or the exact name of the L7 policy.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    listener = lb_pick(lb['listeners'], args[1], 'listener')
    policy = lb_pick(lb_l7_policies(listener), args[2], 'L7 policy')
    lb_render_one('l7policy', policy, "L7 Policy Details", policy_columns(lb, listener), output, network, options) do
      lb_print_section("Rules", policy['rules_expanded'], rule_columns, options, "No rules.")
    end
  end

  protected

  def policy_target(lb, it)
    if !it['redirect_pool_id'].to_s.empty?
      format_lb_pool_ref(lb, it['redirect_pool_id'])
    elsif !it['redirect_url'].to_s.empty?
      it['redirect_url'].to_s
    elsif !it['redirect_prefix'].to_s.empty?
      it['redirect_prefix'].to_s
    else
      ''
    end
  end

  def policy_list_columns(lb)
    {
      "Position" => 'position',
      "ID" => 'id',
      "Name" => 'name',
      "Action" => 'action',
      "Target" => lambda {|it| policy_target(lb, it) },
      "Rules" => lambda {|it| (it['rules_expanded'] || []).size },
    }.merge(lb_status_columns)
  end

  def policy_columns(lb, listener)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Listener" => lambda {|it| listener['name'].to_s.empty? ? listener['id'] : "#{listener['name']} (#{listener['id']})" },
      "Position" => 'position',
      "Action" => 'action',
      "Redirect Pool" => lambda {|it| format_lb_pool_ref(lb, it['redirect_pool_id']) },
      "Redirect URL" => 'redirect_url',
      "Redirect Prefix" => 'redirect_prefix',
      "Redirect HTTP Code" => 'redirect_http_code',
    }.merge(lb_enabled_columns)
  end

  def rule_columns
    {
      "ID" => 'id',
      "Type" => 'type',
      "Compare" => 'compare_type',
      "Key" => 'key',
      "Value" => 'value',
      "Invert" => lambda {|it| format_boolean(it['invert']) },
      "Enabled" => lambda {|it| format_boolean(it['admin_state_up']) },
    }
  end

end
