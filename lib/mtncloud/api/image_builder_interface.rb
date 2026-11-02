require 'mtncloud/api/api_client'
# require 'mtncloud/api/image_builder_image_builds_interface'
# require 'mtncloud/api/image_builder_preseed_scripts_interface'
# require 'mtncloud/api/image_builder_boot_scripts_interface'

class MtnCloud::ImageBuilderInterface < MtnCloud::APIClient

  def image_builds
    MtnCloud::ImageBuilderImageBuildsInterface.new(common_interface_options).setopts(@options)
  end

  def preseed_scripts
    MtnCloud::ImageBuilderPreseedScriptsInterface.new(common_interface_options).setopts(@options)
  end

  def boot_scripts
    MtnCloud::ImageBuilderBootScriptsInterface.new(common_interface_options).setopts(@options)
  end
  
end
