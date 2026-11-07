require 'mtncloud/api/api_client'

# Top-level flat-by-ID host/VM group endpoints (MORPH-14136).
#
# Only show/update/delete are exposed at this path; list/create/form-options
# stay scoped under /clusters/{id}/host-vm-groups and /zones/{id}/host-vm-groups.
# See the platform UI's ApiV1UrlMappings (rc-9.1.0).
class MtnCloud::HostVmGroupsInterface < MtnCloud::APIClient

  def base_path
    "/api/host-vm-groups"
  end

  def get(id, params={})
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { params: params, authorization: "Bearer #{@access_token}" }
    execute(method: :get, url: url, headers: headers)
  end

  def update(id, payload)
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :put, url: url, headers: headers, payload: payload.to_json)
  end

  def destroy(id, params={})
    validate_id!(id)
    url = "#{base_path}/#{id}"
    headers = { :params => params, :authorization => "Bearer #{@access_token}", 'Content-Type' => 'application/json' }
    execute(method: :delete, url: url, headers: headers)
  end

  alias :delete :destroy

end
