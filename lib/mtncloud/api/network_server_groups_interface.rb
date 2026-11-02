require 'mtncloud/api/secondary_rest_interface'

class MtnCloud::NetworkServerGroupsInterface < MtnCloud::SecondaryRestInterface
  def base_path(network_server_id)
    "/api/networks/servers/#{network_server_id}/groups"
  end
end