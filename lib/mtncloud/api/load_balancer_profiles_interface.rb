require 'mtncloud/api/secondary_rest_interface'

class MtnCloud::LoadBalancerProfilesInterface < MtnCloud::SecondaryRestInterface

  def base_path(load_balancer_id)
    "/api/load-balancers/#{load_balancer_id}/profiles"
  end

end
