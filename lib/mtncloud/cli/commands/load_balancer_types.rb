require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::LoadBalancerTypes
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::RestCommand
  include MtnCloud::Cli::LoadBalancersHelper

  set_command_name :'load-balancer-types'
  register_subcommands :list, :get

  # register_interfaces :load_balancer_types

  protected

  def load_balancer_type_list_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
    }
  end

  def load_balancer_type_column_definitions(options)
    {
      "ID" => 'id',
      "Name" => 'name',
      "Code" => 'code',
      "Creatable" => lambda {|it| format_boolean(it['creatable']) },
    }
  end

  # overridden to support name or code
  def find_load_balancer_type_by_name_or_id(name)
    load_balancer_type_for_name_or_id(name)
  end

end

