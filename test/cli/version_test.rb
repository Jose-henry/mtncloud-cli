require 'mtncloud_test'

# Tests for MtnCloud::Cli::VersionCommand
class MtnCloudTest::VersionTest < MtnCloudTest::TestCase
  
  def requires_authentication
    false
  end

  def test_version
  	assert_execute %(version)
  end

  def test_version_short
    assert_execute %(version -v)
    assert_execute %(version --short)
  end

  # def test_version_help
  #   assert_execute %(version --help)
  # end

end