require 'mtncloud/api/rest_interface'

class MtnCloud::CertificatesInterface < MtnCloud::RestInterface

  def base_path
    "/api/certificates"
  end

end
