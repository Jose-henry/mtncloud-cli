require 'mtncloud/cli/cli_command'

class MtnCloud::Cli::NetworkSecurityServerTypes
  include MtnCloud::Cli::CliCommand
  include MtnCloud::Cli::RestCommand
  include MtnCloud::Cli::InfrastructureHelper

  set_command_description "View network security server types"
  set_command_name :'network-security-server-types'
  register_subcommands :list, :get

  # hidden in favor of get-type and list-types
  set_command_hidden

  # register_interfaces :network_security_server_types

  protected

end

