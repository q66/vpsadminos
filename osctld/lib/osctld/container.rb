require 'libosctl'
require 'yaml'
require 'osctld/lockable'
require 'osctld/manipulable'
require 'osctld/assets/definition'

module OsCtld
  class Container
    include Lockable
    include Manipulable
    include Assets::Definition
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include Utils::SwitchUser

    def self.default_dataset(pool, id)
      name = File.join(pool.ct_ds, id)
      OsCtl::Lib::Zfs::Dataset.new(name, base: name)
    end

    attr_inclusive_reader :pool, :id, :user, :dataset, :group, :distribution,
      :version, :arch, :autostart, :ephemeral, :hostname, :dns_resolvers,
      :nesting, :prlimits, :mounts, :migration_log, :netifs, :cgparams,
      :devices, :seccomp_profile, :apparmor, :attrs, :state, :init_pid,
      :lxc_config

    alias_method :ephemeral?, :ephemeral

    # @param pool [Pool]
    # @param id [String]
    # @param user [User, nil]
    # @param group [Group, nil]
    # @param dataset [String, nil]
    # @param opts [Hash] options
    # @option opts [Boolean] load load config
    # @option opts [String] load_from load from this string instead of config file
    # @option opts [Boolean] staged create a staged container
    # @option opts [Boolean] devices determines whether devices are initialized
    def initialize(pool, id, user = nil, group = nil, dataset = nil, opts = {})
      init_lock
      init_manipulable

      opts[:load] = true unless opts.has_key?(:load)

      @pool = pool
      @id = id
      @user = user
      @group = group
      @dataset = dataset
      @state = opts[:staged] ? :staged : :unknown
      @ephemeral = false
      @init_pid = nil
      @netifs = NetInterface::Manager.new(self)
      @cgparams = nil
      @devices = nil
      @prlimits = nil
      @mounts = nil
      @hostname = nil
      @dns_resolvers = nil
      @nesting = false
      @seccomp_profile = nil
      @apparmor = AppArmor.new(self)
      @lxc_config = Container::LxcConfig.new(self)
      @attrs = Attributes.new
      @dist_network_configured = false

      if opts[:load]
       load_config(opts[:load_from], !opts.has_key?(:devices) || opts[:devices])
      end
    end

    def ident
      inclusively { "#{pool.name}:#{id}" }
    end

    def configure(distribution, version, arch)
      exclusively do
        @distribution = distribution
        @version = version
        @arch = arch
        @netifs = NetInterface::Manager.new(self)
        @nesting = false
        @seccomp_profile = default_seccomp_profile
        @cgparams = CGroup::ContainerParams.new(self)
        @devices = Devices::ContainerManager.new(self)
        @prlimits = PrLimits::Manager.default(self)
        @mounts = Mount::Manager.new(self)
        devices.init
        save_config
      end
    end

    def assets
      define_assets do |add|
        # Datasets
        add.dataset(
          dataset,
          desc: "Container's rootfs dataset",
          uidmap: uid_map.map(&:to_a),
          gidmap: gid_map.map(&:to_a),
          user: root_host_uid,
          group: root_host_gid,
          mode: 0770,
          validate_if: mounted?,
        )

        # Directories and files
        add.directory(
          rootfs,
          desc: "Container's rootfs",
          user: root_host_uid,
          group: root_host_gid,
          mode: 0755,
          validate_if: mounted?,
        )

        add.directory(
          user_hook_script_dir,
          desc: 'User supplied script hooks',
          user: 0,
          group: 0,
          mode: 0700
        )
        add.directory(
          lxc_dir,
          desc: 'LXC configuration',
          user: 0,
          group: user.ugid,
          mode: 0750
        )

        lxc_config.assets(add)

        add.file(
          File.join(lxc_dir, '.bashrc'),
          desc: 'Shell configuration file for osctl ct su',
          user: 0,
          group: 0,
          mode: 0644
        )

        add.file(
          config_path,
          desc: 'Container config for osctld',
          user: 0,
          group: 0,
          mode: 0400
        )
        add.file(
          log_path,
          desc: 'LXC log file',
          user: 0,
          group: user.ugid,
          mode: 0660
        )
      end
    end

    # Duplicate the container with a different ID
    #
    # The returned container has `state` set to `:staged` and its assets will
    # not exist, so the caller has to build the container and call
    # `ct.state = :complete` for the container to become usable.
    #
    # @param id [String] new container id
    # @param opts [Hash] options
    # @option opts [Pool] :pool target pool, optional
    # @option opts [User] :user target user, optional
    # @option opts [Group] :group target group, optional
    # @option opts [String] :dataset target dataset, optional
    def dup(id, opts = {})
      ct = clone
      ct.send(:clone_from, self, id, opts)
      ct
    end

    # Mount the container's dataset
    # @param force [Boolean] ensure the datasets are mounted even if osctld
    #                        already mounted them
    def mount(force: false)
      return if !force && mounted
      dataset.mount(recursive: true)
      self.mounted = true
    end

    # Check if the container's dataset is mounted
    # @param force [Boolean] check if the dataset is mounted even if osctld
    #                        already mounted it
    def mounted?(force: false)
      if force || mounted.nil?
        self.mounted = dataset.mounted?(recursive: true)
      else
        mounted
      end
    end

    def chown(user)
      self.user = user
      save_config
      lxc_config.configure
      configure_bashrc
    end

    def chgrp(grp, missing_devices: nil)
      self.group = grp

      case missing_devices
      when 'provide'
        devices.ensure_all
        devices.create

      when 'remove'
        devices.remove_missing
        devices.create

      when 'check'
        devices.check_all_available!(grp)

      else
        fail "unsupported action for missing devices: '#{missing_devices}'"
      end

      save_config
      lxc_config.configure
      configure_bashrc
    end

    def state=(v)
      if state == :staged
        case v
        when :complete
          exclusively { @state = :stopped }
          save_config

        when :running
          exclusively { @state = v }
          save_config
        end

        return
      end

      exclusively { @state = v }
    end

    def current_state
      s = state
      return s if s != :unknown

      ret = ct_control(self, :ct_status, ids: [id])

      if ret[:status]
        self.state = ret[:output][id.to_sym][:state].to_sym

      else
        self.state = :error
      end
    end

    def running?
      state == :running
    end

    def can_start?
      inclusively { state != :staged && state != :error && pool.active? }
    end

    def starting
      self.dist_network_configured = false
    end

    def stopped
      self.dist_network_configured = false
      self.init_pid = nil
    end

    def can_dist_configure_network?
      inclusively do
        next false if netifs.detect { |netif| !netif.can_run_distconfig? }
        true
      end
    end

    def dist_configure_network?
      inclusively do
        !dist_network_configured && can_dist_configure_network?
      end
    end

    def dist_configure_network
      return unless dist_configure_network?

      DistConfig.run(self, :network)
      self.dist_network_configured = true
    end

    def dir
      dataset.mountpoint
    end

    def lxc_home(user: nil, group: nil)
      inclusively { (group || self.group).userdir(user || self.user) }
    end

    def lxc_dir(user: nil, group: nil)
      inclusively { File.join(lxc_home(user: user, group: group), id) }
    end

    def rootfs
      File.join(dir, 'private')

    rescue SystemCommandFailed
      # Dataset for staged containers does not have to exist yet, relevant
      # primarily for ct show/list
      nil
    end

    def runtime_rootfs
      fail 'container is not running' unless running?

      pid = inclusively { init_pid }
      fail 'init_pid not set' unless pid

      File.join('/proc', pid.to_s, 'root')
    end

    def config_path
      inclusively { File.join(pool.conf_path, 'ct', "#{id}.yml") }
    end

    def user_hook_script_dir
      inclusively { File.join(pool.user_hook_script_dir, 'ct', id) }
    end

    def uid_map
      user.uid_map
    end

    def gid_map
      user.gid_map
    end

    def root_host_uid
      user.uid_map.ns_to_host(0)
    end

    def root_host_gid
      user.gid_map.ns_to_host(0)
    end

    # Return a list of all container datasets
    # @return [Array<OsCtl::Lib::Zfs::Dataset>]
    def datasets
      ds = inclusively { dataset }
      [ds] + ds.descendants
    end

    # Iterate over all container datasets
    # @yieldparam ds [OsCtl::Lib::Zfs::Dataset]
    def each_dataset(&block)
      datasets.each(&block)
    end

    def base_cgroup_path
      inclusively { File.join(group.full_cgroup_path(user), "ct.#{id}") }
    end

    def cgroup_path
      File.join(base_cgroup_path, 'user-owned')
    end

    def abs_cgroup_path(subsystem)
      File.join(CGroup::FS, CGroup.real_subsystem(subsystem), cgroup_path)
    end

    def abs_apply_cgroup_path(subsystem)
      File.join(CGroup::FS, CGroup.real_subsystem(subsystem), base_cgroup_path)
    end

    def set(opts)
      opts.each do |k, v|
        case k
        when :autostart
          self.autostart = AutoStart::Config.new(self, v[:priority], v[:delay])

        when :ephemeral
          self.ephemeral = true

        when :hostname
          original = nil

          exclusively do
            original = @hostname
            @hostname = OsCtl::Lib::Hostname.new(v)
          end

          DistConfig.run(self, :set_hostname, original: original)

        when :dns_resolvers
          self.dns_resolvers = v
          DistConfig.run(self, :dns_resolvers)

        when :nesting
          self.nesting = true

        when :distribution
          exclusively do
            @distribution = v[:name]
            @version = v[:version]
            @arch = v[:arch] if v[:arch]
          end

        when :seccomp_profile
          self.seccomp_profile = v

        when :attrs
          attrs.update(v)
        end
      end

      save_config
      lxc_config.configure_base
    end

    def unset(opts)
      opts.each do |k, v|
        case k
        when :autostart
          self.autostart = false

        when :ephemeral
          self.ephemeral = false

        when :hostname
          self.hostname = nil

        when :dns_resolvers
          self.dns_resolvers = nil

        when :nesting
          self.nesting = false

        when :seccomp_profile
          self.seccomp_profile = default_seccomp_profile

        when :attrs
          v.each { |attr| attrs.unset(attr) }
        end
      end

      save_config
      lxc_config.configure_base
    end

    def prlimit_set(name, soft, hard)
      exclusively do
        limit = @prlimits.detect { |v| v.name == name }

        if limit
          limit.set(soft, hard)

        else
          @prlimits << PrLimit.new(name, soft, hard)
        end
      end

      save_config
      lxc_config.configure
    end

    def prlimit_unset(name)
      exclusively do
        limit = @prlimits.detect { |v| v.name == name }
        next unless limit
        @prlimits.delete(limit)
      end

      save_config
      lxc_config.configure_prlimits
    end

    def configure_bashrc
      ErbTemplate.render_to('ct/bashrc', {
        ct: self,
        override: %w(
          attach cgroup console device execute info ls monitor stop top wait
        ),
        disable: %w(
          autostart checkpoint clone copy create destroy freeze snapshot
          start-ephemeral unfreeze unshare
        ),
      }, File.join(lxc_dir, '.bashrc'))
    end

    def open_migration_log(role, opts = {})
      self.migration_log = Migration::Log.new(role: role, opts: opts)
      save_config
    end

    def close_migration_log(save: true)
      self.migration_log = nil
      save_config if save
    end

    # Export to clients
    def export
      inclusively do
        {
          pool: pool.name,
          id: id,
          user: user.name,
          group: group.name,
          dataset: dataset.name,
          rootfs: rootfs,
          lxc_path: lxc_home,
          lxc_dir: lxc_dir,
          group_path: cgroup_path,
          distribution: distribution,
          version: version,
          state: state,
          init_pid: init_pid,
          autostart: autostart ? true : false,
          autostart_priority: autostart && autostart.priority,
          autostart_delay: autostart && autostart.delay,
          ephemeral: ephemeral,
          hostname: hostname,
          dns_resolvers: dns_resolvers,
          nesting: nesting,
          seccomp_profile: seccomp_profile,
          log_file: log_path,
        }.merge!(attrs.export)
      end
    end

    def save_config
      data = dump

      File.open(config_path, 'w', 0400) do |f|
        f.write(YAML.dump(data))
      end

      File.chown(0, 0, config_path)
    end

    def reload_config
      load_config
    end

    # @param config [String]
    def replace_config(config)
      load_config(config)
      save_config
    end

    def log_path
      inclusively { File.join(pool.log_path, 'ct', "#{id}.log") }
    end

    def log_type
      inclusively { "ct=#{pool.name}:#{id}" }
    end

    def manipulation_resource
      ['container', ident]
    end

    protected
    attr_exclusive_writer :pool, :id, :user, :dataset, :group, :distribution,
      :version, :arch, :autostart, :ephemeral, :hostname, :dns_resolvers,
      :nesting, :prlimits, :mounts, :migration_log, :netifs, :cgparams,
      :devices, :seccomp_profile, :apparmor, :attrs, :init_pid, :lxc_config
    attr_synchronized_accessor :mounted, :dist_network_configured

    def load_config(config = nil, init_devices = true)
      if config
        cfg = YAML.load(config)
      else
        cfg = YAML.load_file(config_path)
      end

      exclusively do
        @state = cfg['state'].to_sym if cfg['state']
        @user ||= DB::Users.find(cfg['user'], pool) || (raise "user not found")
        @group ||= DB::Groups.find(cfg['group'], pool) || (raise "group not found")

        unless @dataset
          if cfg['dataset']
            @dataset = OsCtl::Lib::Zfs::Dataset.new(cfg['dataset'], base: cfg['dataset'])
          else
            @dataset = Container.default_dataset(pool, id)
          end
        end

        @distribution = cfg['distribution']
        @version = cfg['version']
        @arch = cfg['arch']
        @autostart = cfg['autostart'] && AutoStart::Config.load(self, cfg['autostart'])
        @ephemeral = cfg['ephemeral']
        @hostname = cfg['hostname'] && OsCtl::Lib::Hostname.new(cfg['hostname'])
        @dns_resolvers = cfg['dns_resolvers']
        @nesting = cfg['nesting'] || false
        @seccomp_profile = cfg['seccomp_profile'] || default_seccomp_profile
        @migration_log = Migration::Log.load(cfg['migration_log']) if cfg['migration_log']
        @cgparams = CGroup::ContainerParams.load(self, cfg['cgparams'])
        @prlimits = PrLimits::Manager.load(self, cfg['prlimits'] || {})
        @attrs = Attributes.load(cfg['attrs'] || {})

        # It's necessary to load devices _before_ netifs. The device manager needs
        # to create cgroups first, in order for echo a > devices.deny to work.
        # If the container has a veth interface, the setup code switches to the
        # container's user, which creates cgroups in all subsystems. Devices then
        # can't be initialized properly.
        @devices = Devices::ContainerManager.load(self, cfg['devices'] || [])
        @devices.init if init_devices

        @netifs = NetInterface::Manager.load(self, cfg['net_interfaces'] || [])
        @mounts = Mount::Manager.load(self, cfg['mounts'] || [])
      end
    end

    # Dump to config
    def dump
      inclusively do
        data = {
          'user' => user.name,
          'group' => group.name,
          'dataset' => dataset.name,
          'distribution' => distribution,
          'version' => version,
          'arch' => arch,
          'net_interfaces' => netifs.dump,
          'cgparams' => cgparams.dump,
          'devices' => devices.dump,
          'prlimits' => prlimits.dump,
          'mounts' => mounts.dump,
          'autostart' => autostart && autostart.dump,
          'ephemeral' => ephemeral,
          'hostname' => hostname && hostname.to_s,
          'dns_resolvers' => dns_resolvers,
          'nesting' => nesting,
          'seccomp_profile' => seccomp_profile == default_seccomp_profile \
                               ? nil : seccomp_profile,
          'attrs' => attrs.dump,
        }

        data['state'] = 'staged' if state == :staged
        data['migration_log'] = migration_log.dump if migration_log

        data
      end
    end

    # Change the container so that it becomes a clone of `ct` with a different id
    # @param ct [Container] the source container
    # @param id [String] new container id
    # @param opts [Hash] options
    # @option opts [Pool] :pool target pool, optional
    # @option opts [User] :user target user, optional
    # @option opts [Group] :group target group, optional
    # @option opts [String] :dataset target dataset, optional
    def clone_from(ct, id, opts = {})
      init_lock
      init_manipulable

      @id = id
      @pool = opts[:pool] if opts[:pool]
      @user = opts[:user] if opts[:user]
      @group = opts[:group] if opts[:group]
      @init_pid = nil
      @state = :staged
      @migration_log = nil

      if opts[:dataset]
        @dataset = OsCtl::Lib::Zfs::Dataset.new(
          opts[:dataset],
          base: opts[:dataset],
        )
      else
        @dataset = Container.default_dataset(@pool, @id)
      end

      @apparmor = @apparmor.dup(self)
      @autostart = @autostart && @autostart.dup(self)
      @cgparams = cgparams.dup(self)
      @prlimits = prlimits.dup(self)
      @mounts = mounts.dup(self)
      @lxc_config = lxc_config.dup(self)
      @attrs = attrs.dup

      @devices = devices.dup(self)
      devices.init

      @netifs = netifs.dup(self)
      netifs.each(&:setup)
    end

    def default_seccomp_profile
      File.join(Lxc::CONFIGS, 'common.seccomp')
    end
  end
end
