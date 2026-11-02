require 'mtncloud/api/rest_interface'

class MtnCloud::SecurityPackagesInterface < MtnCloud::RestInterface

  def base_path
    "/api/security-packages"
  end

end
