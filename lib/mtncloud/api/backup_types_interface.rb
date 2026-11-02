require 'mtncloud/api/read_interface'

class MtnCloud::BackupTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/backup-types"
  end

end