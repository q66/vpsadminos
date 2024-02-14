require 'fileutils'
require 'libosctl'
require 'osctld/lockable'
require 'osctld/manipulable'
require 'osctld/assets/definition'

module OsCtld
  class User
    include Lockable
    include Manipulable
    include Assets::Definition
    include OsCtl::Lib::Utils::Log

    attr_inclusive_reader :pool, :name, :ugid, :uid_map, :gid_map, :standalone, :attrs
    attr_exclusive_writer :registered

    def initialize(pool, name, load: true, config: nil)
      init_lock
      init_manipulable
      @pool = pool
      @name = name
      @attrs = Attributes.new
      load_config(config) if load
    end

    def id
      name
    end

    def ident
      inclusively { "#{pool.name}:#{name}" }
    end

    # @param uid_map [IdMap]
    # @param gid_map [IdMap]
    # @param ugid [Integer, nil]
    # @param standalone [Boolean]
    def configure(uid_map, gid_map, ugid: nil, standalone: true)
      exclusively do
        @ugid = ugid || UGidRegistry.get
        @uid_map = uid_map
        @gid_map = gid_map
        @standalone = standalone
      end

      save_config
    end

    def assets
      define_assets do |add|
        # Directories and files
        add.directory(
          userdir,
          desc: 'User directory',
          user: 0,
          group: ugid,
          mode: 0o751
        )

        add.directory(
          homedir,
          desc: 'Home directory',
          user: ugid,
          group: ugid,
          mode: 0o751
        )

        add.file(
          config_path,
          desc: "osctld's user config",
          user: 0,
          group: 0,
          mode: 0o400
        )

        add.entry('/etc/passwd', desc: 'System user') do |asset|
          asset.validate_block do
            if /^#{Regexp.escape(sysusername)}:x:#{ugid}:#{ugid}:/ !~ File.read(asset.path)
              asset.add_error('entry missing or invalid')
            end
          end
        end

        add.entry('/etc/group', desc: 'System group') do |asset|
          asset.validate_block do
            if /^#{Regexp.escape(sysgroupname)}:x:#{ugid}:$/ !~ File.read(asset.path)
              asset.add_error('entry missing or invalid')
            end
          end
        end
      end
    end

    def registered?
      inclusively { return registered unless registered.nil? }
      v = SystemUsers.include?(sysusername)
      exclusively { self.registered = v }
      v
    end

    # @param opts [Hash]
    # @option opts [true] :standalone
    # @option opts [Hash] :attrs
    def set(opts)
      opts.each do |k, v|
        case k
        when :standalone
          exclusively { @standalone = true }

        when :attrs
          attrs.update(v)

        else
          raise "unsupported option '#{k}'"
        end
      end

      save_config
    end

    # @param opts [Hash]
    # @option opts [true] :standalone
    # @option opts [Array<String>] :attrs
    def unset(opts)
      opts.each do |k, v|
        case k
        when :standalone
          exclusively { @standalone = false }

        when :attrs
          v.each { |attr| attrs.unset(attr) }

        else
          raise "unsupported option '#{k}'"
        end
      end

      save_config
    end

    def sysusername
      "#{pool.name}-#{name}"
    end

    def sysgroupname
      sysusername
    end

    def userdir
      inclusively { File.join(pool.user_dir, name) }
    end

    def homedir
      File.join(userdir, '.home')
    end

    def config_path
      inclusively { File.join(pool.conf_path, 'user', "#{name}.yml") }
    end

    def has_containers?
      ct = DB::Containers.get.detect do |ct|
        ct.user.name == name && ct.pool.name == pool.name
      end
      ct ? true : false
    end

    def containers
      DB::Containers.get do |cts|
        cts.select { |ct| ct.user == self && ct.pool.name == pool.name }
      end
    end

    def id_range_allocation_owner
      "user:#{name}"
    end

    def log_type
      "user=#{ident}"
    end

    def manipulation_resource
      ['user', ident]
    end

    private

    attr_inclusive_reader :registered

    def dump
      inclusively do
        {
          'uid_map' => uid_map.dump,
          'gid_map' => gid_map.dump,
          'standalone' => standalone,
          'attrs' => attrs.dump
        }
      end
    end

    def save_config
      File.open(config_path, 'w', 0o400) do |f|
        f.write(OsCtl::Lib::ConfigFile.dump_yaml(dump))
      end

      File.chown(0, 0, config_path)
    end

    def load_config(config)
      cfg = if config
              OsCtl::Lib::ConfigFile.load_yaml(config)
            else
              OsCtl::Lib::ConfigFile.load_yaml_file(config_path)
            end

      @ugid = SystemUsers.uid_of(sysusername) || UGidRegistry.get
      @uid_map = IdMap.load(cfg['uid_map'], cfg)
      @gid_map = IdMap.load(cfg['gid_map'], cfg)
      @standalone = cfg.has_key?('standalone') ? cfg['standalone'] : true
      @attrs = Attributes.load(cfg['attrs'] || {})
    end
  end
end
