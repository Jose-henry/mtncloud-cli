require 'mtncloud/api/read_interface'

class MtnCloud::NetworkSecurityServerTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/networks/security-server-types"
  end

end
