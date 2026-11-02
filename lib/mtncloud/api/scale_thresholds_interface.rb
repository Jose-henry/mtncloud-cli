require 'mtncloud/api/rest_interface'

class MtnCloud::ScaleThresholdsInterface < MtnCloud::RestInterface

  def base_path
    "/api/scale-thresholds"
  end

end
