require 'test/unit'
require 'mtncloud'

# The platform's own blueprint type is shown as MTN Cloud and can be given as mtncloud,
# while the API keeps its own code for it.
class BlueprintTypeTest < Test::Unit::TestCase

  def setup
    @helper = Object.new.extend(MtnCloud::Cli::ProvisioningHelper)
  end

  def test_native_type_is_shown_as_mtn_cloud
    assert_equal "MTN Cloud", @helper.format_blueprint_type(MtnCloud::Cli::ProvisioningHelper::NATIVE_BLUEPRINT_TYPE)
    assert_equal "MTN Cloud", @helper.format_blueprint_type(MtnCloud::Cli::ProvisioningHelper::NATIVE_BLUEPRINT_TYPE.capitalize)
  end

  def test_other_types_are_shown_as_is
    assert_equal "terraform", @helper.format_blueprint_type("terraform")
    assert_equal "", @helper.format_blueprint_type(nil)
  end

  def test_mtncloud_is_sent_as_the_api_code
    assert_equal MtnCloud::Cli::ProvisioningHelper::NATIVE_BLUEPRINT_TYPE, @helper.parse_blueprint_type("mtncloud")
    assert_equal MtnCloud::Cli::ProvisioningHelper::NATIVE_BLUEPRINT_TYPE, @helper.parse_blueprint_type("MTNCloud")
  end

  def test_other_types_are_sent_as_is
    assert_equal "terraform", @helper.parse_blueprint_type("terraform")
    assert_equal "cloudFormation", @helper.parse_blueprint_type("cloudFormation")
  end
end
