require 'mtncloud/api/read_interface'

class MtnCloud::LoadBalancerTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/load-balancer-types"
  end

end
