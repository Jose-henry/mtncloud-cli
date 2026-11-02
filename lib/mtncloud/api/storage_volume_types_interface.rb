require 'mtncloud/api/read_interface'

class MtnCloud::StorageVolumeTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/storage-volume-types"
  end

end
