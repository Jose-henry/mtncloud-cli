require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::NetworkPoolServerTypes
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::RestCommand
  include MtnCloud::Cli::InfrastructureHelper

  set_command_description "View network pool server types"
  set_command_name :'network-pool-server-types'
  register_subcommands :list, :get

  # hidden in favor of get-type and list-types
  set_command_hidden

  # register_interfaces :network_pool_server_types

  protected

end

