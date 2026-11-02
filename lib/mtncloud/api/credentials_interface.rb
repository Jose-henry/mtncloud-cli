require 'mtncloud/api/rest_interface'

class MtnCloud::CredentialsInterface < MtnCloud::RestInterface

  def base_path
    "/api/credentials"
  end

end
