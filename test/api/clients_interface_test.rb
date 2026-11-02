require 'mtncloud_test'

# Tests for MtnCloud::InstancesInterface
class MtnCloudTest::ClientsInterfaceTest < MtnCloudTest::TestCase
  
  def test_clients_interface
    @clients_interface = client.clients
    response = @clients_interface.list()
    records = response['clients']
    assert records.is_a?(Array)
    if !records.empty?
      response = @clients_interface.get(records[0]['id'])
      record = response['client']
      assert record.is_a?(Hash)
      assert_equal record['id'], records[0]['id']
      assert_equal record['clientId'], records[0]['clientId']
    else
      #puts "No clients found in this environment"
    end
    #todo: create and delete  
  end

end