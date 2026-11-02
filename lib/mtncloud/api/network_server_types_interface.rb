require 'mtncloud/api/read_interface'

class MtnCloud::NetworkServerTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/networks/server-types"
  end

end
