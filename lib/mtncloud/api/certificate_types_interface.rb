require 'mtncloud/api/rest_interface'

class MtnCloud::CertificateTypesInterface < MtnCloud::RestInterface

  def base_path
    "/api/certificate-types"
  end

  def option_types(id, params={}, headers={})
    validate_id!(id)
    execute(method: :get, url: "#{base_path}/#{id}/option-types", params: params, headers: headers)
  end

end
