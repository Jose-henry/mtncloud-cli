require 'mtncloud/cli/cli_command'

# The pools of a load balancer: the groups of members it sends traffic to.
class MtnCloud::Cli::LoadBalancerPools
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View the pools of a load balancer: the groups of members it sends traffic to."
  set_command_name :'load-balancer-pools'
  register_subcommands :list, :get, :add, :update, :remove

  set_subcommand_descriptions({
    'list' => "List a load balancer's pools.",
    'get' => "Show one pool, with its members and health monitor.",
    'add' => "Not available yet.",
    'update' => "Not available yet.",
    'remove' => "Not available yet.",
  })

  def connect(options)
    lb_connect(options)
  end

  def list(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] --network NETWORK"), 1, <<-EOT)
List a load balancer's pools, sorted by name.
#{lb_piece_footer}
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    lb_render_list('pools', lb_sort(lb['pools']), "Pools", lb_pool_list_columns, output, network, options, "No pools.")
  end

  def get(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [pool] --network NETWORK"), 2, <<-EOT)
Show one pool of a load balancer, with its members and health monitor.
#{lb_piece_footer}
[pool] is required. This is the ID or the exact name of the pool.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    pool = lb_pick(lb['pools'], args[1], 'pool')
    lb_render_one('pool', pool, "Pool Details", pool_columns, output, network, options) do
      lb_print_section("Members", lb_sort(pool['members'], 'address'), lb_member_list_columns, options, "No members.")
      monitor = pool['healthmonitor']
      lb_print_section("Health Monitor", monitor.is_a?(Hash) && !monitor['id'].to_s.empty? ? [monitor] : [],
                       {"ID" => 'id', "Name" => 'name', "Type" => 'type', "Delay" => 'delay', "Timeout" => 'timeout',
                        "Max Retries" => 'max_retries'}.merge(lb_status_columns), options, "No health monitor.")
    end
  end

  def add(args)
    lb_unavailable(args, 'add', "Adding a pool isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def update(args)
    lb_unavailable(args, 'update', "Changing a pool isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def remove(args)
    lb_unavailable(args, 'remove', "Deleting a pool isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  protected

  def pool_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Description" => 'description',
      "Protocol" => 'protocol',
      "Algorithm" => 'lb_algorithm',
      "Session Persistence" => lambda {|it| format_lb_session_persistence(it['session_persistence']) },
      "TLS to Members" => lambda {|it| format_boolean(it['tls_enabled']) },
      "Listeners" => lambda {|it| format_lb_list((it['listeners'] || []).collect {|l| l.is_a?(Hash) ? l['id'] : l }) },
    }.merge(lb_enabled_columns)
  end

end
