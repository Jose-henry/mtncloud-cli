require 'mtncloud/api/rest_interface'

class MtnCloud::SecurityScansInterface < MtnCloud::RestInterface

  def base_path
    "/api/security-scans"
  end

end
