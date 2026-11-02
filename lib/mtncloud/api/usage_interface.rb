require 'mtncloud/api/api_client'

class MtnCloud::UsageInterface < MtnCloud::APIClient

  def base_path
    "/api/usage" # not /usages ?
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

  def get(id, params={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}", params: params)
  end

end
