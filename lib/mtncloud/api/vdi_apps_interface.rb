require 'mtncloud/api/rest_interface'

class MtnCloud::VdiAppsInterface < MtnCloud::RestInterface

  def base_path
    "/api/vdi-apps"
  end

end
