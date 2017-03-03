require 'puppet/provider/iispowershell'
require 'json'

Puppet::Type.type(:iis_pool).provide(:powershell, parent: Puppet::Provider::Iispowershell) do
  def initialize(value = {})
    super(value)
    @property_flush = {
      'poolattrs' => {}
    }
  end

  def self.poolattrs
    {
      enable_32_bit: 'enable32BitAppOnWin64',
      runtime: 'managedRuntimeVersion',
      pipeline: 'managedPipelineMode'
    }
  end

  def self.pipelines
    {
      0 => 'Integrated',
      1 => 'Classic'
    }
  end

  def self.instances
    pools = []
    inst_cmd = 'Import-Module WebAdministration;gci "IIS:\AppPools" | %{ Get-ItemProperty $_.PSPath | Select Name, State, enable32BitAppOnWin64, managedRuntimeVersion, managedPipelineMode  } | ConvertTo-Json -depth 4'
    result = run(inst_cmd)
    unless result.empty?
      pool_names = JSON.parse(result)
      pool_names = [pool_names] if pool_names.is_a?(Hash)
      pool_names.each do |pool|
        pools << new(ensure: pool['state'].downcase,
                     name: pool['name'],
                     enable_32_bit: ((pool['enable32BitAppOnWin64']).to_s.to_sym || :false),
                     runtime: ((pool['managedRuntimeVersion']).empty? ? :no_managed_code : (pool['managedRuntimeVersion'])),
                     pipeline: pool['managedPipelineMode'])
      end
    end

    pools
  end

  def self.prefetch(resources)
    pools = instances
    resources.keys.each do |pool|
      # rubocop:disable Lint/AssignmentInCondition
      if provider = pools.find { |p| p.name == pool }
        resources[pool].provider = provider
      end
    end
  end

  def exists?
    %w(stopped started).include?(@property_hash[:ensure])
  end

  mk_resource_methods

  def create
    inst_cmd = "Import-Module WebAdministration; New-WebAppPool -Name \"#{@resource[:name]}\""
    Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |property, value|
      if value == 'managedRuntimeVersion' && @resource[property] == :no_managed_code then
        actual_value = '""'
      elsif value == 'managedPipelineMode' then
        case @resource[property]
        when :Integrated, 'Integrated'
          actual_value = 0
        when :Classic, 'Classic'
          actual_value = 1
        else
          actual_value = @resource[property]
        end
      else
        actual_value = @resource[property]
      end

      inst_cmd += "; Set-ItemProperty \"IIS:\\\\AppPools\\#{@resource[:name]}\" #{value} #{actual_value}" if @resource[property]
    end

    Puppet.debug "Powershell: #{inst_cmd}"

    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    Puppet.debug "Creation powershell response was #{resp}"

    @resource.original_parameters.each_key do |k|
      @property_hash[k] = @resource[k]
    end
    @property_hash[:ensure] = :present unless @property_hash[:ensure]

    exists? ? (return true) : (return false)
  end

  def destroy
    inst_cmd = "Import-Module WebAdministration; Remove-WebAppPool -Name \"#{@resource[:name]}\""
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?

    @property_hash.clear
    exists? ? (return false) : (return true)
  end

  Puppet::Type::Iis_pool::ProviderPowershell.poolattrs.each do |property, poolattr|
    define_method "#{property}=" do |value|
      @property_flush['poolattrs'][poolattr] = value
      @property_hash[property] = value
    end
  end

  def restart
    inst_cmd = "Import-Module WebAdministration; Restart-WebAppPool -Name \"#{@resource[:name]}\""
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?
  end

  def start
    create unless exists?
    @property_hash[:name] = @resource[:name]
    @property_flush['state'] = :Started
    @property_hash[:ensure] = 'started'
  end

  def stop
    create unless exists?
    @property_hash[:name] = @resource[:name]
    @property_flush['state'] = :Stopped
    @property_hash[:ensure] = 'stopped'
  end

  def enabled?
    inst_cmd = "Import-Module WebAdministration; (Get-WebAppPoolState -Name \"#{@resource[:name]}\").value"
    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd).rstrip
    case resp
    when 'Started'
      true
    else
      false
    end
  end

  def flush
    command_array = []
    command_array << 'Import-Module WebAdministration; '
    if @property_flush['state']
      state_cmd = if @property_flush['state'] == :Started
                    'Start-WebAppPool'
                  else
                    'Stop-WebAppPool'
                  end
      state_cmd += " -Name \"#{@property_hash[:name]}\""
      command_array << state_cmd
    end
    @property_flush['poolattrs'].each do |poolattr, value|
      if poolattr == 'managedRuntimeVersion' && value == :no_managed_code then
        actual_value = '""'
      elsif poolattr == 'managedPipelineMode' then
        case value
        when :Integrated, 'Integrated'
          actual_value = 0
        when :Classic, 'Classic'
          actual_value = 1
        else
          actual_value = value
        end
      else
        actual_value = value
      end
      command_array << "Set-ItemProperty \"IIS:\\\\AppPools\\#{@property_hash[:name]}\" #{poolattr} #{actual_value}"
    end

    inst_cmd = command_array.join('; ')
    Puppet.debug "Powershell: #{inst_cmd}"

    resp = Puppet::Type::Iis_pool::ProviderPowershell.run(inst_cmd)
    raise(resp) unless resp.empty?
  end
end
