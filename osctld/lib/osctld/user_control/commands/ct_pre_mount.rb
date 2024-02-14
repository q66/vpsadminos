require 'libosctl'
require 'osctld/user_control/commands/base'

module OsCtld
  class UserControl::Commands::CtPreMount < UserControl::Commands::Base
    handle :ct_pre_mount

    include OsCtl::Lib::Utils::Log

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      return error('container not found') unless ct
      return error('access denied') unless owns_ct?(ct)

      Hook.run(
        ct,
        :pre_mount,
        rootfs_mount: opts[:rootfs_mount],
        ns_pid: opts[:client_pid]
      )
      ok
    rescue HookFailed => e
      error(e.message)
    end
  end
end
