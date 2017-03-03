Puppet::Type.newtype(:iis_pool) do
  desc 'The iis_pool type creates and manages IIS application pools'

  newproperty(:ensure) do
    desc 'Whether a pool should be started.'

    newvalue(:stopped) do
      provider.stop
    end

    newvalue(:started) do
      provider.start
    end

    newvalue(:present) do
      provider.create
    end

    newvalue(:absent) do
      provider.destroy
    end

    aliasvalue(:false, :stopped)
    aliasvalue(:true, :started)
  end

  newparam(:name, namevar: true) do
    desc 'This is the name of the application pool'
    validate do |value|
      raise("#{name} is not a valid applcation pool name") unless value =~ %r{^[a-zA-Z0-9\-\_\.'\s]+$}
    end
  end

  newproperty(:enable_32_bit) do
    desc 'If 32-bit is enabled for the pool'
    newvalues(:false, :true)
    defaultto :false
  end

  newproperty(:runtime) do
    desc '.NET runtime version for the pool'
    newvalues(/^v\d+\.\d+$/, :no_managed_code)

    validate do |value|
      raise("#{runtime} must be a float or no_managed_code") unless value =~ %r{^(v?\d+\.\d+)$|^no_managed_code$}
    end
  end

  newproperty(:pipeline) do
    desc 'The pipeline mode for the application pool'
    newvalues(:Integrated, :Classic, :integrated, :classic)
    munge(&:capitalize)
  end

  def refresh
    if self[:ensure] == :present && (provider.enabled? || self[:ensure] == 'started')
      provider.restart
    else
      debug 'Skipping restart; pool is not running'
    end
  end
end
