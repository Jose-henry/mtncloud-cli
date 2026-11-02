require 'mtncloud/cli/cli_command'
require 'mtncloud/cli/commands/catalog_item_types_command'

class MtnCloud::Cli::SelfServiceCommand
  include MtnCloud::Cli::CliCommand

  set_command_name :'self-service'
  set_command_description "Deprecated and replaced by catalog-item-types"

  set_command_hidden
  
  def handle(args)
  	print_error yellow,"[DEPRECATED] The command `self-service` is deprecated and replaced by `catalog-item-types`.",reset,"\n"
  	MtnCloud::Cli::CatalogItemTypesCommand.new.handle(args)
  end

end
