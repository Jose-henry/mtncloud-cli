require 'mtncloud/api/api_client'

class MtnCloud::ActivityInterface < MtnCloud::APIClient

  def list(params={})
    execute(method: :get, url: "/api/activity", headers: {params: params})
  end

end
