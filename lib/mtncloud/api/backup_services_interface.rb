require 'mtncloud/api/rest_interface'

class MtnCloud::BackupServicesInterface < MtnCloud::RestInterface

  def base_path
    "/api/backup-services"
  end

end
