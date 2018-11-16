require 'libosctl'
require 'osctld/lockable'
require 'osctld/manipulable'
require 'osctld/assets/definition'

module OsCtld
  # This class represents a data pool
  #
  # Data pool contains users, groups and containers, both data
  # and configuration. Each user/group/ct belongs to exactly one pool.
  class Pool
    PROPERTY_ACTIVE = 'org.vpsadminos.osctl:active'
    PROPERTY_DATASET = 'org.vpsadminos.osctl:dataset'
    USER_DS = 'user'
    CT_DS = 'ct'
    CONF_DS = 'conf'
    HOOK_DS = 'hook'
    LOG_DS = 'log'
    REPOSITORY_DS = 'repository'

    OPTIONS = %i(parallel_start parallel_stop)

    include Lockable
    include Manipulable
    include Assets::Definition
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System
    include OsCtl::Lib::Utils::File

    attr_reader :name, :dataset, :state, :migration_key_chain, :autostart_plan,
      :attrs

    def initialize(name, dataset)
      init_lock
      init_manipulable

      @name = name
      @dataset = dataset || name
      @state = :active
      @attrs = Attributes.new

      load_config

      @migration_key_chain = Migration::KeyChain.new(self)
      @autostart_plan = AutoStart::Plan.new(self)
    end

    def id
      name
    end

    def pool
      self
    end

    def assets
      define_assets do |add|
        # Datasets
        add.dataset(
          ds(USER_DS),
          desc: 'Contains user homes and LXC configuration',
          user: 0,
          group: 0,
          mode: 0511
        )
        add.dataset(
          ds(CT_DS),
          desc: 'Contains container root filesystems',
          user: 0,
          group: 0,
          mode: 0511
        )
        add.dataset(
          ds(CONF_DS),
          desc: 'Configuration files',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.dataset(
          ds(HOOK_DS),
          desc: 'User supplied script hooks',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.dataset(
          ds(LOG_DS),
          desc: 'Container log files, pool history',
          user: 0,
          group: 0,
          mode: 0511
        )
        add.dataset(
          ds(REPOSITORY_DS),
          desc: 'Local template repository cache',
          user: Repository::UID,
          group: 0,
          mode: 0500
        )

        # Configs
        add.directory(
          File.join(conf_path, 'pool'),
          desc: 'Pool configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.file(
          config_path,
          desc: 'Pool configuration file for osctld',
          optional: true
        )
        add.directory(
          File.join(conf_path, 'user'),
          desc: 'User configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.directory(
          File.join(conf_path, 'group'),
          desc: 'Group configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.directory(
          File.join(conf_path, 'ct'),
          desc: 'Container configuration files for osctld',
          user: 0,
          group: 0,
          mode: 0500
        )
        add.directory(
          File.join(conf_path, 'migration'),
          desc: 'Identity and authorized keys for migrations',
          user: 0,
          group: 0,
          mode: 0500
        )

        # Logs
        add.directory(
          File.join(log_path, 'ct'),
          desc: 'Container log files',
          user: 0,
          group: 0
        )

        # Hooks
        add.directory(
          File.join(user_hook_script_dir, 'ct'),
          desc: 'User supplied container script hooks',
          user: 0,
          group: 0
        )

        # Pool history
        History.assets(pool, add)

        # Migration
        migration_key_chain.assets(add)

        # Runstate
        add.directory(
          run_dir,
          desc: 'Runtime configuration',
          user: 0,
          group: 0,
          mode: 0711
        )
        add.directory(
          console_dir,
          desc: 'Sockets for container consoles',
          user: 0,
          group: 0,
          mode: 0711
        )
        add.directory(
          devices_dir,
          desc: 'Device nodes for containers',
          user: 0,
          group: 0,
          mode: 0711
        )
        add.directory(
          hook_dir,
          desc: 'Container hooks',
          user: 0,
          group: 0,
          mode: 0711
        )
        add.directory(
          mount_dir,
          desc: 'Mount helper directories for containers',
          user: 0,
          group: 0,
          mode: 0711
        )
        add.directory(
          apparmor_dir,
          desc: 'AppArmor files',
          user: 0,
          group: 0,
          mode: 0700
        )

        AppArmor.assets(add, pool)
      end
    end

    def setup
      # Ensure needed datasets are present
      mkdatasets

      # Setup run state, i.e. hooks
      runstate

      # Load users from zpool
      load_users

      # Register loaded users into the system
      Commands::User::Register.run(all: true)

      # Generate /etc/subuid and /etc/subgid
      Commands::User::SubUGIds.run

      # Load groups
      load_groups

      # Load containers from zpool
      load_cts

      # Setup AppArmor profiles
      AppArmor.setup_pool(pool)

      # Allow containers to create veth interfaces
      Commands::User::LxcUsernet.run

      # Load migration keys
      migration_key_chain.setup

      # Load repositories
      load_repositories

      # Open history
      History.open(self)
    end

    # Set pool options
    # @param opts [Hash]
    # @option opts [Integer] :parallel_start
    # @option opts [Integer] :parallel_stop
    # @option opts [Hash] :attrs
    def set(opts)
      opts.each do |k, v|
        case k
        when :parallel_start
          instance_variable_set(:"@#{k}", opts[k])
          pool.autostart_plan.resize(opts[k])

        when :parallel_stop
          instance_variable_set(:"@#{k}", opts[k])

        when :attrs
          attrs.update(v)

        else
          fail "unsupported option '#{k}'"
        end
      end

      save_config
    end

    # Reset pool options
    # @param opts [Hash]
    # @option opts [Array<Symbol>] :options
    # @option opts [Array<String>] :attrs
    def unset(opts)
      opts.each do |k, v|
        case k
        when :options
          OPTIONS.each do |opt|
            next unless v.include?(opt)

            remove_instance_variable(:"@#{opt}")
          end

        when :attrs
          v.each { |attr| attrs.unset(attr) }
        end
      end

      save_config
    end

    def autostart
      autostart_plan.start
    end

    def stop
      autostart_plan.stop
    end

    def active?
      state == :active
    end

    def disable
      @state = :disabled
    end

    def ct_ds
      ds(CT_DS)
    end

    def user_ds
      ds(USER_DS)
    end

    def conf_path
      path(CONF_DS)
    end

    def log_path
      path(LOG_DS)
    end

    def user_hook_script_dir
      path(HOOK_DS)
    end

    def repo_path
      path(REPOSITORY_DS)
    end

    def log_type
      "pool=#{name}"
    end

    def manipulation_resource
      ['pool', name]
    end

    def run_dir
      File.join(RunState::POOL_DIR, name)
    end

    def devices_dir
      File.join(run_dir, 'devices')
    end

    def hook_dir
      File.join(run_dir, 'hooks')
    end

    def console_dir
      File.join(run_dir, 'console')
    end

    def mount_dir
      File.join(run_dir, 'mounts')
    end

    def apparmor_dir
      File.join(run_dir, 'apparmor')
    end

    def config_path
      File.join(conf_path, 'pool', 'config.yml')
    end

    # Pool option accessors
    OPTIONS.each do |k|
      define_method(k) do
        v = instance_variable_get("@#{k}")
        v.nil? ? default_opts[k] : v
      end
    end

    protected
    def load_config
      return unless File.exist?(config_path)

      cfg = YAML.load_file(config_path)

      @parallel_start = cfg['parallel_start']
      @parallel_stop = cfg['parallel_stop']
      @attrs = Attributes.load(cfg['attrs'] || {})
    end

    def default_opts
      {
        parallel_start: 2,
        parallel_stop: 4,
      }
    end

    def dump_opts
      ret = {}

      OPTIONS.each do |k|
        v = instance_variable_get("@#{k}")
        ret[k.to_s] = v unless v.nil?
      end

      ret
    end

    def save_config
      regenerate_file(config_path, 0400) do |f|
        f.write(YAML.dump(dump_opts.merge(attrs.dump)))
      end
    end

    def mkdatasets
      log(:info, "Ensuring presence of base datasets and directories")
      zfs(:create, '-p', ds(USER_DS))
      zfs(:create, '-p', ds(CT_DS))
      zfs(:create, '-p', ds(CONF_DS))
      zfs(:create, '-p', ds(HOOK_DS))
      zfs(:create, '-p', ds(LOG_DS))
      zfs(:create, '-p', ds(REPOSITORY_DS))

      File.chmod(0511, path(USER_DS))
      File.chmod(0511, path(CT_DS))
      File.chmod(0500, path(CONF_DS))
      File.chmod(0500, path(HOOK_DS))
      File.chmod(0511, path(LOG_DS))

      File.chown(Repository::UID, 0, path(REPOSITORY_DS))
      File.chmod(0500, path(REPOSITORY_DS))

      # Configuration directories
      %w(pool ct group user migration repository).each do |dir|
        path = File.join(conf_path, dir)
        Dir.mkdir(path, 0500) unless Dir.exist?(path)
      end

      [
        File.join(user_hook_script_dir, 'ct'),
        File.join(log_path, 'ct'),
      ].each do |path|
        Dir.mkdir(path) unless Dir.exist?(path)
      end
    end

    def load_users
      log(:info, "Loading users")

      Dir.glob(File.join(conf_path, 'user', '*.yml')).each do |f|
        name = File.basename(f)[0..(('.yml'.length+1) * -1)]
        u = User.new(self, name)
        next unless check_user_conflict(u)

        DB::Users.add(u)
        UserControl::Supervisor.start_server(u)
      end
    end

    def load_groups
      log(:info, "Loading groups")
      DB::Groups.setup(self)

      rx = /^#{Regexp.escape(File.join(conf_path, 'group'))}(.*)\/config\.yml$/

      Dir.glob(File.join(conf_path, 'group', '**', 'config.yml')).each do |file|
        next unless rx =~ file
        name = $1
        next if ['', '/default'].include?(name)

        DB::Groups.add(Group.new(self, name, devices: false))
      end

      # The devices in the root group have to be configured as soon as possible,
      # because `echo a > devices.deny` will not work when the root cgroup has
      # any children.
      root = DB::Groups.root(self)

      # Initialize devices of all groups, from the root group down
      root.descendants.each do |grp|
        grp.devices.init
      end
    end

    def load_cts
      log(:info, "Loading containers")

      Dir.glob(File.join(conf_path, 'ct', '*.yml')).each do |f|
        ctid = File.basename(f)[0..(('.yml'.length+1) * -1)]

        ct = Container.new(self, ctid)
        ensure_limits(ct)
        ct.lxc_config.configure
        Monitor::Master.monitor(ct)
        Console.reconnect_tty0(ct) if ct.current_state == :running
        DB::Containers.add(ct)
      end
    end

    def load_repositories
      log(:info, "Loading repositories")
      DB::Repositories.setup(self)

      Dir.glob(File.join(conf_path, 'repository', '*.yml')).each do |f|
        name = File.basename(f)[0..(('.yml'.length+1) * -1)]
        next if name == 'default'

        repo = Repository.new(self, name)
        DB::Repositories.add(repo)
      end
    end

    def runstate
      Dir.mkdir(run_dir, 0711) unless Dir.exist?(run_dir)

      [console_dir, devices_dir, hook_dir, mount_dir].each do |dir|
        Dir.mkdir(dir, 0711) unless Dir.exist?(dir)
      end

      [apparmor_dir].each do |dir|
        Dir.mkdir(dir, 0700) unless Dir.exist?(dir)
      end

      %w(
        ct-pre-start
        ct-pre-mount
        ct-post-mount
        ct-autodev
        ct-on-start
        ct-post-stop
      ).each do |hook|
        symlink = OsCtld.hook_run(hook, self)
        File.symlink(OsCtld::hook_src(hook), symlink) unless File.symlink?(symlink)
      end
    end

    def check_user_conflict(user)
      DB::Users.get.each do |u|
        if u.name == user.name
          log(
            :warn,
            "Unable to load user '#{user.name}': "+
            "name already taken by pool '#{u.pool.name}'"
          )
          return false

        elsif u.ugid == user.ugid
          log(
            :warn,
            "Unable to load user '#{user.name}': "+
            "user/group ID #{user.ugid} already taken by pool '#{u.pool.name}'"
          )
          return false
        end
      end

      true
    end

    def ensure_limits(ct)
      if ct.prlimits.contains?('nofile')
        SystemLimits.ensure_nofile(ct.prlimits['nofile'].hard)
      end
    end

    def ds(path)
      File.join(dataset, path)
    end

    def path(ds = '')
      File.join('/', dataset, ds)
    end
  end
end
