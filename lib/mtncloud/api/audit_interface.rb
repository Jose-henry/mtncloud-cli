require 'mtncloud/api/read_interface'

class MtnCloud::AuditInterface < MtnCloud::ReadInterface

  def base_path
    "/api/audit"
  end

end
