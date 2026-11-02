require 'mtncloud/api/secondary_rest_interface'

class MtnCloud::LoadBalancerPoolNodesInterface < MtnCloud::SecondaryRestInterface

  def base_path(pool_id)
    "/api/load-balancer-pools/#{pool_id}/nodes"
  end
end
