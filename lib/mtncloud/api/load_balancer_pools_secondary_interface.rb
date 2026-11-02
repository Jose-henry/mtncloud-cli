require 'mtncloud/api/secondary_rest_interface'

class MtnCloud::LoadBalancerPoolsSecondaryInterface < MtnCloud::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/pools"
  end

end
