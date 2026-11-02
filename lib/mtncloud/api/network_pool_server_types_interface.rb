require 'mtncloud/api/read_interface'

class MtnCloud::NetworkPoolServerTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/networks/pool-server-types"
  end

end
