require 'mtncloud/api/api_client'
# require 'mtncloud/api/monitoring_checks_interface'
# require 'mtncloud/api/monitoring_groups_interface'
# require 'mtncloud/api/monitoring_apps_interface'
# require 'mtncloud/api/monitoring_incidents_interface'
# require 'mtncloud/api/monitoring_contacts_interface'
# require 'mtncloud/api/monitoring_alerts_interface'

class MtnCloud::MonitoringInterface < MtnCloud::APIClient

  def checks
    MtnCloud::MonitoringChecksInterface.new(common_interface_options).setopts(@options)
  end

  def groups
    MtnCloud::MonitoringGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def apps
    MtnCloud::MonitoringAppsInterface.new(common_interface_options).setopts(@options)
  end

  def incidents
    MtnCloud::MonitoringIncidentsInterface.new(common_interface_options).setopts(@options)
  end

  def contacts
    MtnCloud::MonitoringContactsInterface.new(common_interface_options).setopts(@options)
  end

  def alerts
    MtnCloud::MonitoringAlertsInterface.new(common_interface_options).setopts(@options)
  end
  
end
