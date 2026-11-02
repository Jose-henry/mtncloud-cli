require 'mtncloud/api/rest_interface'

class MtnCloud::VirtualSwitchesInterface < MtnCloud::RestInterface

  def base_path
    "/api/virtual-switches"
  end

end
