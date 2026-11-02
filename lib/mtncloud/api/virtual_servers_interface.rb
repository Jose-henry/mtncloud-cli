require 'mtncloud/api/rest_interface'

class MtnCloud::VirtualServersInterface < MtnCloud::RestInterface

  def base_path
    "/api/load-balancer-virtual-servers"
  end

end
