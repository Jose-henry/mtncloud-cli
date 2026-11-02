require 'mtncloud/api/rest_interface'

class MtnCloud::LoadBalancerPoolsInterface < MtnCloud::RestInterface

  def base_path
    "/api/load-balancer-pools"
  end

end
