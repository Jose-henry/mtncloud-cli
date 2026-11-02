require 'mtncloud/api/api_client'

class MtnCloud::WhoamiInterface < MtnCloud::APIClient

  def default_timeout
    5
  end

  def get(params={})
    execute(method: :get, url: "/api/whoami", params: params)
  end

end
