require 'mtncloud/api/read_interface'

class MtnCloud::CredentialTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/credential-types"
  end

end
