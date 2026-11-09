require 'mtncloud/cli/cli_command'

# The members of a load balancer pool: the backends it sends traffic to.
class MtnCloud::Cli::LoadBalancerMembers
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View the members of a load balancer pool: the backends it sends traffic to."
  set_command_name :'load-balancer-members'
  register_subcommands :list, :get

  set_subcommand_descriptions({
    'list' => "List the members of a pool.",
    'get' => "Show one member of a pool.",
  })

  def connect(options)
    lb_connect(options)
  end

  def handle(args)
    handle_subcommand(args)
  end

  def list(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [pool] --network NETWORK"), 2, <<-EOT)
List the members of a pool, sorted by address.
#{lb_piece_footer}
[pool] is required. This is the ID or the exact name of the pool.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    pool = lb_pick(lb['pools'], args[1], 'pool')
    lb_render_list('members', lb_sort(pool['members'], 'address'), "Members of Pool #{pool['name'].to_s.empty? ? pool['id'] : pool['name']}",
                   lb_member_list_columns, output, network, options, "No members.")
  end

  def get(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [pool] [member] --network NETWORK"), 3, <<-EOT)
Show one member of a pool.
#{lb_piece_footer}
[pool] is required. This is the ID or the exact name of the pool.
[member] is required. This is the ID or the exact name of the member. A member's name is
often empty: use its ID then, or list the pool's members.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    pool = lb_pick(lb['pools'], args[1], 'pool')
    member = lb_pick(pool['members'], args[2], 'member')
    lb_render_one('member', member, "Member Details", member_columns(pool), output, network, options)
  end

  protected

  def member_columns(pool)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Pool" => lambda {|it| pool['name'].to_s.empty? ? pool['id'] : "#{pool['name']} (#{pool['id']})" },
      "Address" => 'address',
      "Port" => 'protocol_port',
      "Weight" => 'weight',
      "Backup" => lambda {|it| format_boolean(it['backup']) },
      "Subnet" => 'subnet_id',
      "Monitor Address" => 'monitor_address',
      "Monitor Port" => 'monitor_port',
    }.merge(lb_enabled_columns)
  end

end
