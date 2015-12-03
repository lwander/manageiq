class ManageIQ::Providers::Google::CloudManager < ManageIQ::Providers::CloudManager
  require_nested :AvailabilityZone
  require_nested :Flavor
  require_nested :RefreshParser
  require_nested :RefreshWorker
  require_nested :Refresher
  require_nested :Template
  require_nested :Vm

  def self.ems_type
    @ems_type ||= "gce".freeze
  end

  def self.description
    @description ||= "Google Compute Engine".freeze
  end

  def self.hostname_required?
    false
  end

  def self.region_required?
    false
  end

  def supported_auth_types
    %w(
      oauth
      auth_key
    )
  end

  # TODO(lwander) determine if user wants to use OAUTH or a service account
  def missing_credentials?(_type = {})
    false
  end

  def supports_authentication?(authtype)
    supported_auth_types.include?(authtype.to_s)
  end

  validates :provider_region, :inclusion => {:in => ManageIQ::Providers::Google::Regions.names}

  def description
    ManageIQ::Providers::Google::Regions.find_by_name(provider_region)[:description]
  end

  def verify_credentials(auth_type = nil, options = {})
    begin
      options[:auth_type] = auth_type

      connection = connect(options)

      # Not all errors will cause Fog to raise an exception,
      # for example an error in the google_project id will
      # succeed to connect but the first API call will raise
      # an exception, so make a simple call to the API to
      # confirm everything is working
      connection.regions.all
    rescue => err
      raise MiqException::MiqInvalidCredentialsError, err.message
    end

    true
  end

  #
  # Connections
  #

  def connect(options = {})
    require 'fog/google'

    raise MiqException::MiqHostError, "No credentials defined" if self.missing_credentials?

    auth_token = authentication_token(options[:auth_type])

    ::Fog::Compute.new(
      :provider               => "Google",
      :google_project         => project,
      :google_json_key_string => auth_token,
    )

  end

  def gce
    @gce ||= connect(:service => "GCE")
  end

  # Operations

  def vm_start(vm, _options = {})
    vm.provider_object.servers.get(vm.name, vm.availability_zone.name).start
    vm.update_attributes!(:raw_power_state => "VM starting")
  rescue => err
  end

  def vm_stop(vm, _options = {})
    vm.provider_object.servers.get(vm.name, vm.availability_zone.name).stop
    vm.update_attributes!(:raw_power_state => "VM stopping")
  rescue => err
  end

  def vm_restart(vm, _options = {})
    vm.provider_object.servers.get(vm.name, vm.availability_zone.name).restart
    vm.update_attributes!(:raw_power_state => "VM starting")
  rescue => err
  end

end
