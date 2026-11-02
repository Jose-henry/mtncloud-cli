require 'mtncloud/api/rest_interface'

class MtnCloud::SearchInterface < MtnCloud::APIClient

  def base_path
    "/api/search"
  end

  def list(params={})
    execute(method: :get, url: "#{base_path}", params: params)
  end

end
