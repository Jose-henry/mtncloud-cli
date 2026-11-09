require 'mtncloud/cli/cli_command'

# The health monitors of a load balancer: each checks the members of one pool.
class MtnCloud::Cli::LoadBalancerMonitors
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::LoadBalancerOperationsHelper

  set_command_description "View the health monitors of a load balancer: each checks the members of one pool."
  set_command_name :'load-balancer-monitors'
  register_subcommands :list, :get, :add, :update, :remove

  set_subcommand_descriptions({
    'list' => "List a load balancer's health monitors.",
    'get' => "Show one health monitor.",
    'add' => "Not available yet.",
    'update' => "Not available yet.",
    'remove' => "Not available yet.",
  })

  def connect(options)
    lb_connect(options)
  end

  def list(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] --network NETWORK"), 1, <<-EOT)
List a load balancer's health monitors (one per pool at most), sorted by pool name.
#{lb_piece_footer}
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    lb_render_list('monitors', lb_monitors(lb), "Health Monitors", monitor_list_columns, output, network, options,
                   "No health monitors.")
  end

  def get(args)
    options, network = lb_piece_parse(args, subcommand_usage("[load balancer] [monitor] --network NETWORK"), 2, <<-EOT)
Show one health monitor of a load balancer.
#{lb_piece_footer}
[monitor] is required. This is the ID or the exact name of the health monitor.
EOT
    output, lb = lb_piece_read(network, args[0], options)
    return 0, nil if output.nil?
    monitor = lb_pick(lb_monitors(lb), args[1], 'health monitor')
    lb_render_one('monitor', monitor, "Health Monitor Details", monitor_columns, output, network, options)
  end

  def add(args)
    lb_unavailable(args, 'add', "Adding a health monitor isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def update(args)
    lb_unavailable(args, 'update', "Changing a health monitor isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  def remove(args)
    lb_unavailable(args, 'remove', "Deleting a health monitor isn't available in the CLI yet. Use the MTN Cloud console.")
  end

  protected

  def monitor_pool(it)
    it['pool_name'].to_s.empty? ? it['pool_id'].to_s : "#{it['pool_name']} (#{it['pool_id']})"
  end

  def monitor_list_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Pool" => lambda {|it| monitor_pool(it) },
      "Type" => 'type',
      "Delay" => 'delay',
      "Timeout" => 'timeout',
      "Max Retries" => 'max_retries',
    }.merge(lb_status_columns)
  end

  def monitor_columns
    {
      "ID" => 'id',
      "Name" => 'name',
      "Pool" => lambda {|it| monitor_pool(it) },
      "Type" => 'type',
      "Delay (s)" => 'delay',
      "Timeout (s)" => 'timeout',
      "Max Retries" => 'max_retries',
      "Max Retries Down" => 'max_retries_down',
      "HTTP Method" => 'http_method',
      "URL Path" => 'url_path',
      "Expected Codes" => 'expected_codes',
    }.merge(lb_enabled_columns)
  end

end
