require 'osctld/lockable'

module OsCtld
  # LXC configuration generator
  class Container::LxcConfig
    include Lockable

    def initialize(ct)
      init_lock
      @ct = ct
    end

    def assets(add)
      add.file(
        config_path,
        desc: 'LXC config',
        user: 0,
        group: 0,
        mode: 0o644
      )
    end

    def configure
      exclusively do
        ErbTemplate.render_to('ct/config', {
          distribution: ct.get_run_conf.distribution,
          version: ct.get_run_conf.version,
          ct:,
          cgparams: ct.cgparams,
          prlimits: ct.prlimits,
          netifs: ct.netifs,
          mounts: ct.mounts.all_entries,
          raw: ct.raw_configs.lxc
        }, config_path)
      end
    end

    alias configure_base configure
    alias configure_cgparams configure
    alias configure_prlimits configure
    alias configure_network configure
    alias configure_mounts configure

    def config_path
      File.join(ct.lxc_dir, 'config')
    end

    def dup(new_ct)
      ret = super()
      ret.init_lock
      ret.instance_variable_set('@ct', new_ct)
      ret
    end

    protected

    attr_reader :ct
  end
end
