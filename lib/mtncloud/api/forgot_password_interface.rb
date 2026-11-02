require 'mtncloud/api/api_client'
# There is no Authorization required for this API.
class MtnCloud::ForgotPasswordInterface < MtnCloud::APIClient

  def authorization_required?
    false
  end

  def send_email(payload, params={})
    execute(method: :post, url: "/api/forgot/send-email", params: params, payload: payload.to_json)
  end

  def reset_password(payload, params={})
    execute(method: :post, url: "/api/forgot/reset-password", params: params, payload: payload.to_json)
  end

end
