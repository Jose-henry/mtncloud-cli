require 'mtncloud/api/rest_interface'

class MtnCloud::StorageServersInterface < MtnCloud::RestInterface

  def base_path
    "/api/storage-servers"
  end

end
