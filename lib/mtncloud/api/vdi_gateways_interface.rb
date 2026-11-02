require 'mtncloud/api/rest_interface'

class MtnCloud::VdiGatewaysInterface < MtnCloud::RestInterface

  def base_path
    "/api/vdi-gateways"
  end

end
