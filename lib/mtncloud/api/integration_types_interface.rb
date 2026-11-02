require 'mtncloud/api/read_interface'

class MtnCloud::IntegrationTypesInterface < MtnCloud::ReadInterface

  def base_path
    "/api/integration-types"
  end

  def option_types(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/option-types", params: params, headers: headers)
  end

end
