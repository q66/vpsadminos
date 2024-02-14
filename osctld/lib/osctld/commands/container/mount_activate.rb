require 'osctld/commands/logged'

module OsCtld
  class Commands::Container::MountActivate < Commands::Logged
    handle :ct_mount_activate

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      ct = DB::Containers.find(opts[:id], opts[:pool])
      error!('container not found') unless ct

      manipulate(ct) do
        error!('the container has to be running') if ct.current_state != :running
        ct.mounts.activate(opts[:mountpoint])
        ok
      end
    rescue MountNotFound
      error!('mount not found')
    rescue MountInvalid => e
      error!(e.message)
    end
  end
end
