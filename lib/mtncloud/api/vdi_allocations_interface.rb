require 'mtncloud/api/read_interface'

class MtnCloud::VdiAllocationsInterface < MtnCloud::ReadInterface

  def base_path
    "/api/vdi-allocations"
  end

end
