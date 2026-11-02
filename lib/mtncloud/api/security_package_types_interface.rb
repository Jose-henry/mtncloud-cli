require 'mtncloud/api/read_interface'

class MtnCloud::SecurityPackageTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/security-package-types"
  end

end
