require 'mtncloud_test'

# Tests for MtnCloud::WhoamiInterface
class MtnCloudTest::WhoamiInterfaceTest < MtnCloudTest::TestCase
  
  def test_whoami_interface
    @whoami_interface = client.whoami
    response = @whoami_interface.get()
    assert_equal response['user']['username'], @config.username
    # todo: fix this, can be cached and fail
    #assert_equal response['appliance']['buildVersion'], MtnCloud::Cli::Remote.load_remote(@config.remote_name)[:build_version]
  end

end