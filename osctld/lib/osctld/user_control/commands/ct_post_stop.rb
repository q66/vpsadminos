require 'libosctl'
require 'osctld/user_control/commands/base'

module OsCtld
  class UserControl::Commands::CtPostStop < UserControl::Commands::Base
    handle :ct_post_stop

    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::Exception

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      return error('container not found') unless ct
      return error('access denied') unless owns_ct?(ct)

      if AppArmor.enabled?
        # Unload AppArmor profile and destroy namespace
        ct.apparmor.destroy_namespace
        ct.apparmor.unload_profile
      end

      if opts[:target] == 'reboot'
        log(:info, ct, 'Reboot requested')
        ct.run_conf.request_reboot
      end

      ct.stopped

      # User-defined hook
      Hook.run(ct, :post_stop)

      ok

    rescue HookFailed => e
      log(:warn, ct, 'Error during post-stop hook')
      log(:warn, ct, "#{e.class}: #{e.message}")
      log(:warn, ct, denixstorify(e.backtrace).join("\n"))
      error(e.message)
    end
  end
end
