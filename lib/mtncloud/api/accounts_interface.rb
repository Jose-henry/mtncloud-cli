require 'mtncloud/api/rest_interface'

class MtnCloud::AccountsInterface < MtnCloud::RestInterface

  def base_path
    "/api/accounts"
  end

end
