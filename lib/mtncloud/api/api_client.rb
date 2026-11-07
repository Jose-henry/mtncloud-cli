require 'json'
require 'uri'
require 'cgi'
require 'mtncloud/rest_client'
#require 'mtncloud/api/body_io'
# require 'rest-client'

class MtnCloud::APIClient

  # This is the OAuth client ID the appliance accepts for CLI logins.
  # It is not branding, do not rename it for MTN Cloud or authentication will break.
  CLIENT_ID = 'morph-cli' unless defined?(CLIENT_ID)

  # Initialize a new APIClient
  #   client = APIClient.new(url:"https://mtncloud.example.com", verify_ssl:false)
  # This old method signature is being deprecated:
  #   client = APIClient.new(access_token, refresh_token, expires_in, base_url, verify_ssl, options={})
  #
  # def initialize(attrs={}, options={})
  def initialize(access_token, refresh_token=nil,expires_in = nil, base_url=nil, verify_ssl=true, options={})
    self.client_id = CLIENT_ID
    attrs = {}
    if access_token.is_a?(Hash)
      attrs = access_token.clone()
      access_token = attrs[:access_token]
      refresh_token = attrs[:refresh_token]
      base_url = attrs[:url] || attrs[:base_url]
      expires_in = attrs[:expires_in]
      verify_ssl = attrs.key?(:verify_ssl) ? attrs[:verify_ssl] : true
      self.client_id = attrs[:client_id] ? attrs[:client_id] : CLIENT_ID
      if attrs[:client_id]
        self.client_id = attrs[:client_id]
      end
      options = refresh_token.is_a?(Hash) ? refresh_token.clone() : {}
    end
    @access_token = access_token
    @refresh_token = refresh_token
    @base_url = base_url
    if @base_url.to_s.empty?
      raise "#{self.class} initialized without a required option :url"
    end
    @base_url = @base_url.chomp("/")
    # todo: validate URI
    @expires_at = nil
    if expires_in != nil
      @expires_at = Time.now + expires_in
    end
    @dry_run = false
    set_ssl_verification_enabled(verify_ssl)
    setopts(options)
  end

  def url
    @base_url
  end

  def to_s
    "<##{self.class}:#{self.object_id.to_s(8)} @url=#{@base_url} @verify_ssl=#{@verify_ssl} @access_token=#{@access_token ? '************' : nil} @refresh_token=#{@access_token ? '************' : nil} @expires_at=#{@expires_at} @client_id=#{@client_id} @options=#{@options}>"
  end

  def inspect
    to_s
  end

  def dry_run(val=true)
    @dry_run = !!val
    self
  end

  def dry()
    dry_run(true)
  end

  def ssl_verification_enabled?
    @verify_ssl
  end

  def set_ssl_verification_enabled(val)
    @verify_ssl = !!val
  end

  # set this in your interface, eg. to 'application/json'
  # or let it it default to json when payload is present.
  def default_content_type
    nil
  end

  # set default seconds for interface to timeout after
  # or let it use system default? none, it should not timeout by default..
  # I think execute() may use 30 seconds for get by default.
  # and it should remove timeout when method is post, put, or delete
  def default_timeout
    nil
  end

  # Authorization is required, except for a couple commands like Ping and Setup
  def authorization_required?
    true
  end

  # common global options, hooray.
  # this is probably needed for CliCommand too..
  # maybe make this a mixin...

  # need this accessor?
  # def get_options
  #   @options
  # end

  # set common global @options for use with all requests
  # meant for inline use just like dry(), set_options(dry_run:true) can be used in place of dry()
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # Example:
  # Prints curl -XGET .../whoami -H "Bearer" instead of actually request
  # APIClient.new(token).whoami.setopts(curl:true).get({})
  # @return self (APIClient)
  def setopts(new_options)
    @options = new_options
    if @options[:dry_run]
      dry_run(true)
    end
    self
  end

  # with_options sets common global @options for the duration of the block only
  # then returns the options to their prior values
  # @param opts [Hash] globally supported options like :dry_run, :json, :curl, :headers, :timeout, etc
  # @return result of block, usually the a result Hash from client.execute({})
  def withopts(tmp_options, &block)
    @_old_options = @options
    begin
      @options = tmp_options
      result = block.call()
    ensure
      @options = @_old_options
    end
    return result
  end

  alias :set_options :setopts
  alias :with_options :withopts
  # Execute an HTTP request with this client.
  # opts - Hash of options for HTTP Request.
  #   :url - The full url
  #   :method - The default method is :get (GET)
  #   :headers - Hash of headers to include in the request.
  #              eg. {'Content-Type' => 'application/json'}. :params is a special key for query parameters.
  #   :params - query parameters
  #   :payload - The body of the request.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  # options - Hash of common global options that commands parse. eg. :headers, :timeout, :dry_run, :curl, etc
  #   :headers - Extra headers to add. This expects a Hash like {'Content-Type' => 'application/json'}.
  #   :timeout - A custom timeout in seconds for api requests. The default is 30. todo: separate timeout options
  def execute(opts, options={})
    # MtnCloud::Logging::DarkPrinter.puts "MtnCloud::RestClient.execute(#{opts})" if MtnCloud::Logging.debug?
    # ok, always prepend @base_url, let the caller specify it exactly or leave it off.
    # this allows the Interface definition be lazy and not specify the base_url in every call to execute()
      # it will be used though...
    if opts[:url]
      if !opts[:url].include?(@base_url)
        opts[:url] = "#{@base_url}#{opts[:url]}"
      end
    end
    # merge in common global @options
    if @options
      options = options.merge(@options)
    else
      options = options.clone
    end

    # determine HTTP method
    if opts[:method].nil?
      opts[:method] = :get
    else
      # convert to lowercase Symbol like :get, :post, :put, or :delete
      opts[:method] = opts[:method].to_s.downcase.to_sym
    end

    # could validate method here...

    # apply default headers
    opts[:headers] ||= {}

    is_multipart = (opts[:payload].is_a?(Hash) && opts[:payload][:multipart] == true)

    # Authorization: apply our access token
    if authorization_required?
      if @access_token
        if opts[:headers][:authorization].nil? && opts[:headers]['Authorization'].nil?
          opts[:headers][:authorization] = "Bearer #{@access_token}"
        else
          # authorization header has already been set.
        end
      end
    end

    # POST and PUT requests default Content-Type is application/json
    # set Content-Type or pass :form_data => true if you want application/x-www-form-urlencoded
    # or use opts[:payload][:multipart] = true if you need multipart/form-data
    if opts[:method] == :post || opts[:method] == :put
      if opts[:headers]['Content-Type'].nil? && opts[:payload] && is_multipart != true && opts[:form_data] != true
        opts[:headers]['Content-Type'] = (default_content_type || 'application/json')
      end

      # Auto encode payload as JSON, just to be nice
      if opts[:headers]['Content-Type'] == 'application/json' && !opts[:payload].is_a?(String)
        opts[:payload] = opts[:payload].to_json
      end

    end

    # always use custom timeout eg. from --timeout option
    # or use default_timeout for GET requests only.
    if opts[:timeout].nil?
      if options[:timeout]
        opts[:timeout] = options[:timeout].to_f
      elsif default_timeout && opts[:method] == :get
        opts[:timeout] = default_timeout.to_f
      end
    end

    # add extra headers, eg. from --header option
    # headers should be a Hash and not an Array, dont make me split you here!
    if options[:headers]
      opts[:headers] = opts[:headers].merge(options[:headers])
    end

    # this is confusing, but RestClient expects :params inside the headers...?
    # move/copy params to headers.params for simplification.
    # remove this if issues arise
    # if opts[:params] && (opts[:headers][:params].nil? || opts[:headers][:params].empty?)
    #   opts[:headers][:params] = opts.delete(:params) # .delete(:params) maybe?
    # end

    # :command_options for these
    # if options[:curl]
    #   opts[:curl] = options[:curl]
    # end
    # if options.key?(:pretty_json)
    #   opts[:pretty_json] = options[:pretty_json]
    # end
    # if options.key?(:scrub)
    #   opts[:scrub] = options[:scrub]
    # end

    # @verify_ssl is not used atm
    # todo: finish this and use it instead of the global variable RestClient.ssl_verification_enabled?
    # gotta clean up all APIClient subclasses new() methods to support this
    # the CliCommand subclasses should be changed to @foos_interface = @api_client.foos
    # also.. Credentials.new()
    if @verify_ssl == false
      opts[:verify_ssl] = OpenSSL::SSL::VERIFY_NONE
    end

    if @dry_run
      # JD: could return a Request object instead...
      # print_dry_run needs options somehow...
      opts[:command_options] = options # trash this..we got @options with setopts now
      return opts
    end

    # uhh can't use LIST at the moment
    # fix it!
    # if opts[:method] == :list
    #   opts[:method]
    # end

    # MtnCloud::Logging::DarkPrinter.puts "MtnCloud::RestClient.execute(#{opts})" if MtnCloud::Logging.debug?
    # instead, using ::RestClient.log = STDOUT
    response = MtnCloud::RestClient.execute(opts)
    if opts[:parse_json] != false && options[:parse_json] != false
      return JSON.parse(response.to_s)
    else
      return response
    end
  end

  def logged_in?
    !!@access_token
  end

  def client_id
    @client_id
  end

  def client_id=(val)
    @client_id = val
  end

  def login(username, password, use_client_id=nil)
    if use_client_id
      self.client_id = use_client_id
    end
    @access_token, @refresh_token, @expires_at = nil, nil, nil
    response = auth.login(username, password, self.client_id)
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    # return response
    return self
  end

  def use_refresh_token(t=nil)
    if t.nil?
      t = @refresh_token
    end
    if t.nil?
      raise "#{self.class} does not currently have a refresh_token"
    end
    response = auth.use_refresh_token(t, self.client_id)
    @access_token = response['access_token']
    @refresh_token = response['refresh_token']
    if response['expires_in'] != nil
      @expires_at = Time.now + response['expires_in']
    end
    @access_token = response['access_token']
    # return response
    return self
  end

  def logout
    @access_token = nil
    @refresh_token = nil
    @expires_at = nil
    return self
  end

  def common_interface_options
    {
      url:           @base_url,
      access_token:  @access_token,
      refresh_token: @refresh_token,
      expires_at:    @expires_at,
      client_id:     @client_id,
      verify_ssl:    @verify_ssl
    }
  end

  def ping
    MtnCloud::PingInterface.new(common_interface_options).setopts(@options)
  end

  def setup
    MtnCloud::SetupInterface.new(common_interface_options).setopts(@options)
  end

  def auth
    MtnCloud::AuthInterface.new({url: @base_url, client_id: @client_id, verify_ssl: @verify_ssl}).setopts(@options)
  end

  def forgot
    MtnCloud::ForgotPasswordInterface.new(common_interface_options).setopts(@options)
  end

  def whoami
    MtnCloud::WhoamiInterface.new(common_interface_options).setopts(@options)
  end

  def search
    MtnCloud::SearchInterface.new(common_interface_options).setopts(@options)
  end

  def user_settings
    MtnCloud::UserSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def dashboard
    MtnCloud::DashboardInterface.new(common_interface_options).setopts(@options)
  end

  def activity
    MtnCloud::ActivityInterface.new(common_interface_options).setopts(@options)
  end

  def options
    MtnCloud::OptionsInterface.new(common_interface_options).setopts(@options)
  end

  def groups
    MtnCloud::GroupsInterface.new(common_interface_options).setopts(@options)
  end

  def account_groups
    MtnCloud::AccountGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def clouds
    MtnCloud::CloudsInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_datastores
    MtnCloud::CloudDatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_resource_pools
    MtnCloud::CloudResourcePoolsInterface.new(common_interface_options).setopts(@options)
  end

  def resource_pool_groups
    MtnCloud::ResourcePoolGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_folders
    MtnCloud::CloudFoldersInterface.new(common_interface_options).setopts(@options)
  end

  def datastores
    MtnCloud::DatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def servers
    MtnCloud::ServersInterface.new(common_interface_options).setopts(@options)
  end

  def systems
    MtnCloud::SystemsInterface.new(common_interface_options).setopts(@options)
  end

  def system_types
    MtnCloud::SystemTypesInterface.new(common_interface_options).setopts(@options)
  end

  def server_devices
    MtnCloud::ServerDevicesInterface.new(common_interface_options).setopts(@options)
  end

  def instances
    MtnCloud::InstancesInterface.new(common_interface_options).setopts(@options)
  end

  def appliance_settings
    MtnCloud::ApplianceSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_settings
    MtnCloud::ProvisioningSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_licenses
    MtnCloud::ProvisioningLicensesInterface.new(common_interface_options).setopts(@options)
  end

  def provisioning_license_types
    MtnCloud::ProvisioningLicenseTypesInterface.new(common_interface_options).setopts(@options)
  end

  def containers
    MtnCloud::ContainersInterface.new(common_interface_options).setopts(@options)
  end

  def instance_types
    MtnCloud::InstanceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def integrations
    MtnCloud::IntegrationsInterface.new(common_interface_options).setopts(@options)
  end

  def integration_types
    MtnCloud::IntegrationTypesInterface.new(common_interface_options).setopts(@options)
  end

  def jobs
    MtnCloud::JobsInterface.new(common_interface_options).setopts(@options)
  end

  def server_types
    MtnCloud::ServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def provision_types
    MtnCloud::ProvisionTypesInterface.new(common_interface_options).setopts(@options)
  end

  def service_plans
    MtnCloud::ServicePlansInterface.new(common_interface_options).setopts(@options)
  end

  def price_sets
    MtnCloud::PriceSetsInterface.new(common_interface_options).setopts(@options)
  end

  def prices
    MtnCloud::PricesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancers
    MtnCloud::LoadBalancersInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_types
    MtnCloud::LoadBalancerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_operations
    MtnCloud::LoadBalancerOperationsInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_virtual_servers
    MtnCloud::LoadBalancerVirtualServersInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pools
    MtnCloud::LoadBalancerPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pools_secondary
    MtnCloud::LoadBalancerPoolsSecondaryInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_profiles
    MtnCloud::LoadBalancerProfilesInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_monitors
    MtnCloud::LoadBalancerMonitorsInterface.new(common_interface_options).setopts(@options)
  end

  def load_balancer_pool_nodes
    MtnCloud::LoadBalancerPoolNodesInterface.new(common_interface_options).setopts(@options)
  end

  def tasks
    MtnCloud::TasksInterface.new(common_interface_options).setopts(@options)
  end

  def task_sets
    MtnCloud::TaskSetsInterface.new(common_interface_options).setopts(@options)
  end

  def virtual_images
    MtnCloud::VirtualImagesInterface.new(common_interface_options).setopts(@options)
  end

  def apps
    MtnCloud::AppsInterface.new(common_interface_options).setopts(@options)
  end

  def blueprints
    MtnCloud::BlueprintsInterface.new(common_interface_options).setopts(@options)
  end

  def deploy
    MtnCloud::DeployInterface.new(common_interface_options).setopts(@options)
  end

  def deployments
    MtnCloud::DeploymentsInterface.new(common_interface_options).setopts(@options)
  end

  def security_groups
    MtnCloud::SecurityGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def security_group_rules
    MtnCloud::SecurityGroupRulesInterface.new(common_interface_options).setopts(@options)
  end

  def clusters
    MtnCloud::ClustersInterface.new(common_interface_options).setopts(@options)
  end

  def affinity_groups
    MtnCloud::AffinityGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def host_vm_groups
    MtnCloud::HostVmGroupsInterface.new(common_interface_options).setopts(@options)
  end


  def accounts
    MtnCloud::AccountsInterface.new(common_interface_options).setopts(@options)
  end

  def approvals
    MtnCloud::ApprovalsInterface.new(common_interface_options).setopts(@options)
  end

  def users
    MtnCloud::UsersInterface.new(common_interface_options).setopts(@options)
  end

  def account_users
    MtnCloud::AccountUsersInterface.new(common_interface_options).setopts(@options)
  end

  def user_groups
    MtnCloud::UserGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def user_sources
    MtnCloud::UserSourcesInterface.new(common_interface_options).setopts(@options)
  end

  def logs
    MtnCloud::LogsInterface.new(common_interface_options).setopts(@options)
  end

  def roles
    MtnCloud::RolesInterface.new(common_interface_options).setopts(@options)
  end

  def key_pairs
    MtnCloud::KeyPairsInterface.new(common_interface_options).setopts(@options)
  end

  def distributed_workers
    MtnCloud::DistributedWorkersInterface.new(common_interface_options).setopts(@options)
  end

  def certificates
    MtnCloud::CertificatesInterface.new(common_interface_options).setopts(@options)
  end

  def certificate_types
    MtnCloud::CertificateTypesInterface.new(common_interface_options).setopts(@options)
  end

  def license
    MtnCloud::LicenseInterface.new(common_interface_options).setopts(@options)
  end

  def option_types
    MtnCloud::OptionTypesInterface.new(common_interface_options).setopts(@options)
  end

  def option_type_lists
    MtnCloud::OptionTypeListsInterface.new(common_interface_options).setopts(@options)
  end

  def option_type_forms
    MtnCloud::OptionTypeFormsInterface.new(common_interface_options).setopts(@options)
  end

  def scale_thresholds
    MtnCloud::ScaleThresholdsInterface.new(common_interface_options).setopts(@options)
  end

  def power_schedules
    MtnCloud::PowerSchedulesInterface.new(common_interface_options).setopts(@options)
  end

  def execute_schedules
    MtnCloud::ExecuteSchedulesInterface.new(common_interface_options).setopts(@options)
  end

  def monitoring
    MtnCloud::MonitoringInterface.new(common_interface_options).setopts(@options)
  end

  # def checks
  #   # MtnCloud::MonitoringChecksInterface.new(common_interface_options).setopts(@options)
  #   monitoring.checks
  # end

  # def incidents
  #   # MtnCloud::MonitoringIncidentsInterface.new(common_interface_options).setopts(@options)
  #   monitoring.incidents
  # end

  def policies
    MtnCloud::PoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def group_policies
    MtnCloud::GroupPoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def cloud_policies
    MtnCloud::CloudPoliciesInterface.new(common_interface_options).setopts(@options)
  end

  def networks
    MtnCloud::NetworksInterface.new(common_interface_options).setopts(@options)
  end

  def network_types
    MtnCloud::NetworkTypesInterface.new(common_interface_options).setopts(@options)
  end

  def subnets
    MtnCloud::SubnetsInterface.new(common_interface_options).setopts(@options)
  end

  def subnet_types
    MtnCloud::SubnetTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_groups
    MtnCloud::NetworkGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def network_pools
    MtnCloud::NetworkPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_ips
    MtnCloud::NetworkPoolIpsInterface.new(common_interface_options).setopts(@options)
  end

  def network_routers
    MtnCloud::NetworkRoutersInterface.new(common_interface_options).setopts(@options)
  end

  def network_services
    MtnCloud::NetworkServicesInterface.new(common_interface_options).setopts(@options)
  end

  # def network_service_types
  #   MtnCloud::NetworkServiceTypesInterface.new(common_interface_options).setopts(@options)
  # end

  def network_security_servers
    MtnCloud::NetworkSecurityServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_security_server_types
    MtnCloud::NetworkSecurityServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_servers
    MtnCloud::NetworkPoolServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_pool_server_types
    MtnCloud::NetworkPoolServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_domains
    MtnCloud::NetworkDomainsInterface.new(common_interface_options).setopts(@options)
  end

  def network_domain_records
    MtnCloud::NetworkDomainRecordsInterface.new(common_interface_options).setopts(@options)
  end

  def network_proxies
    MtnCloud::NetworkProxiesInterface.new(common_interface_options).setopts(@options)
  end

  def archive_buckets
    MtnCloud::ArchiveBucketsInterface.new(common_interface_options).setopts(@options)
  end

  def archive_files
    MtnCloud::ArchiveFilesInterface.new(common_interface_options).setopts(@options)
  end

  def image_builder
    MtnCloud::ImageBuilderInterface.new(common_interface_options).setopts(@options)
  end

  def storage_providers
    MtnCloud::StorageProvidersInterface.new(common_interface_options).setopts(@options)
  end

  def storage_servers
    MtnCloud::StorageServersInterface.new(common_interface_options).setopts(@options)
  end

  def storage_server_types
    MtnCloud::StorageServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_volumes
    MtnCloud::StorageVolumesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_volume_types
    MtnCloud::StorageVolumeTypesInterface.new(common_interface_options).setopts(@options)
  end

  def storage_datastores
    MtnCloud::StorageDatastoresInterface.new(common_interface_options).setopts(@options)
  end

  def library_instance_types
    MtnCloud::LibraryInstanceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def library_layouts
    MtnCloud::LibraryLayoutsInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_upgrades
    MtnCloud::LibraryContainerUpgradesInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_types
    MtnCloud::LibraryContainerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_scripts
    MtnCloud::LibraryContainerScriptsInterface.new(common_interface_options).setopts(@options)
  end

  def library_container_templates
    MtnCloud::LibraryContainerTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_cluster_layouts
    MtnCloud::LibraryClusterLayoutsInterface.new(common_interface_options).setopts(@options)
  end

  def library_cluster_packages
    MtnCloud::LibraryClusterPackagesInterface.new(common_interface_options).setopts(@options)
  end

  def library_spec_templates
    MtnCloud::LibrarySpecTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_spec_template_types
    MtnCloud::LibrarySpecTemplateTypesInterface.new(common_interface_options).setopts(@options)
  end

  def packages
    MtnCloud::PackagesInterface.new(common_interface_options).setopts(@options)
  end

  def plugins
    MtnCloud::PluginsInterface.new(common_interface_options).setopts(@options)
  end

  def cypher
    MtnCloud::CypherInterface.new(common_interface_options).setopts(@options)
  end

  def old_cypher
    MtnCloud::OldCypherInterface.new(common_interface_options).setopts(@options)
  end

  def execution_request
    MtnCloud::ExecutionRequestInterface.new(common_interface_options).setopts(@options)
  end

  def file_copy_request
    MtnCloud::FileCopyRequestInterface.new(common_interface_options).setopts(@options)
  end

  def processes
    MtnCloud::ProcessesInterface.new(common_interface_options).setopts(@options)
  end

  def reports
    MtnCloud::ReportsInterface.new(common_interface_options).setopts(@options)
  end

  def environments
    MtnCloud::EnvironmentsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_settings
    MtnCloud::BackupSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def guidance_settings
    MtnCloud::GuidanceSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def log_settings
    MtnCloud::LogSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def monitoring_settings
    MtnCloud::MonitoringSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def whitelabel_settings
    MtnCloud::WhitelabelSettingsInterface.new(common_interface_options).setopts(@options)
  end

  def wiki
    MtnCloud::WikiInterface.new(common_interface_options).setopts(@options)
  end

  def health
    MtnCloud::HealthInterface.new(common_interface_options).setopts(@options)
  end

  def hub
    MtnCloud::HubInterface.new(common_interface_options).setopts(@options)
  end

  def audit
    MtnCloud::AuditInterface.new(common_interface_options).setopts(@options)
  end

  def budgets
    MtnCloud::BudgetsInterface.new(common_interface_options).setopts(@options)
  end

  def invoices
    MtnCloud::InvoicesInterface.new(common_interface_options).setopts(@options)
  end

  def invoice_line_items
    MtnCloud::InvoiceLineItemsInterface.new(common_interface_options).setopts(@options)
  end

  def guidance
    MtnCloud::GuidanceInterface.new(common_interface_options).setopts(@options)
  end

  def projects
    MtnCloud::ProjectsInterface.new(common_interface_options).setopts(@options)
  end

  def backups
    MtnCloud::BackupsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_jobs
    MtnCloud::BackupJobsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_results
    MtnCloud::BackupResultsInterface.new(common_interface_options).setopts(@options)
  end

  def backup_restores
    MtnCloud::BackupRestoresInterface.new(common_interface_options).setopts(@options)
  end

  def backup_services
    MtnCloud::BackupServicesInterface.new(common_interface_options).setopts(@options)
  end

  def backup_service_types
    MtnCloud::BackupServiceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def backup_types
    MtnCloud::BackupTypesInterface.new(common_interface_options).setopts(@options)
  end

  def catalog_item_types
    MtnCloud::CatalogItemTypesInterface.new(common_interface_options).setopts(@options)
  end

  def catalog
    MtnCloud::ServiceCatalogInterface.new(common_interface_options).setopts(@options)
  end

  def usage
    MtnCloud::UsageInterface.new(common_interface_options).setopts(@options)
  end

  def billing
    MtnCloud::BillingInterface.new(common_interface_options).setopts(@options)
  end

  def vdi
    MtnCloud::VdiInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_pools
    MtnCloud::VdiPoolsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_allocations
    MtnCloud::VdiAllocationsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_apps
    MtnCloud::VdiAppsInterface.new(common_interface_options).setopts(@options)
  end

  def vdi_gateways
    MtnCloud::VdiGatewaysInterface.new(common_interface_options).setopts(@options)
  end

  def network_servers
    MtnCloud::NetworkServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_types
    MtnCloud::NetworkServerTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_groups
    MtnCloud::NetworkServerGroupsInterface.new(common_interface_options).setopts(@options)
  end

  def network_server_services
    MtnCloud::NetworkServerServicesInterface.new(common_interface_options).setopts(@options)
  end

  def network_resource_types
    MtnCloud::NetworkResourceTypesInterface.new(common_interface_options).setopts(@options)
  end

  def network_edge_clusters
    MtnCloud::NetworkEdgeClustersInterface.new(common_interface_options).setopts(@options)
  end

  def network_dhcp_servers
    MtnCloud::NetworkDhcpServersInterface.new(common_interface_options).setopts(@options)
  end

  def network_dhcp_relays
    MtnCloud::NetworkDhcpRelaysInterface.new(common_interface_options).setopts(@options)
  end
  
  def network_static_routes
    MtnCloud::NetworkStaticRoutesInterface.new(common_interface_options).setopts(@options)
  end

  def snapshots
    MtnCloud::SnapshotsInterface.new(common_interface_options).setopts(@options)
  end

  def credentials
    MtnCloud::CredentialsInterface.new(common_interface_options).setopts(@options)
  end

  def credential_types
    MtnCloud::CredentialTypesInterface.new(common_interface_options).setopts(@options)
  end

  def clients
    MtnCloud::ClientsInterface.new(common_interface_options).setopts(@options)
  end

  def security_packages
    MtnCloud::SecurityPackagesInterface.new(common_interface_options).setopts(@options)
  end

  def security_package_types
    MtnCloud::SecurityPackageTypesInterface.new(common_interface_options).setopts(@options)
  end

  def security_scans
    MtnCloud::SecurityScansInterface.new(common_interface_options).setopts(@options)
  end

  def network_floating_ips
    MtnCloud::NetworkFloatingIpsInterface.new(common_interface_options).setopts(@options)
  end
  
  def email_templates
    MtnCloud::EmailTemplatesInterface.new(common_interface_options).setopts(@options)
  end

  def library_operating_systems
    MtnCloud::LibraryOperatingSystemsInterface.new(common_interface_options).setopts(@options)
  end

  def migrations
    MtnCloud::MigrationsInterface.new(common_interface_options).setopts(@options)
  end

  def tokens
    MtnCloud::TokensInterface.new(common_interface_options).setopts(@options)
  end

  def virtual_switches
    MtnCloud::VirtualSwitchesInterface.new(common_interface_options).setopts(@options)
  end

  def rest(endpoint)
    MtnCloud::RestInterface.new(common_interface_options).setopts(@options.merge({base_path: "#{@base_url}/api/#{endpoint}"}))
  end

  def interface(type)
    type = type.to_s.singularize.underscore
    interface_name = type.pluralize
    if !respond_to?(interface_name)
      raise "#{self.class} has not defined an interface method named '#{interface_name}'"
    end
    return send(interface_name)
  end
  alias :get_interface :interface

  def support_bundles
    MtnCloud::SupportBundlesInterface.new(common_interface_options).setopts(@options)
  end

  # add new interfaces here

  protected

  def validate_id!(id, param_name='id')
    if !(id.is_a?(String) || id.is_a?(Integer))
      raise "#{self.class} passed an invalid #{param_name}! Expected String or Integer and got (#{id.class}) #{id.inspect}"
    elsif id.to_s.strip.empty?
      raise "#{self.class} passed a blank #{param_name}!"
    end
    return true
  end

end
