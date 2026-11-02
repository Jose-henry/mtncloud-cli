require 'mtncloud/api/read_interface'

class MtnCloud::InvoiceLineItemsInterface < MtnCloud::ReadInterface

  def base_path
    "/api/invoice-line-items"
  end

end
