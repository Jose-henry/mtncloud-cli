require 'mtncloud/api/read_interface'

class MtnCloud::BackupServiceTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/backup-service-types"
  end

end