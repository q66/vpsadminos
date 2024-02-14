require 'osctld/commands/logged'

module OsCtld
  class Commands::Container::Move < Commands::Logged
    handle :ct_move

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      state = ct.exclusively { ct.state }

      manipulate(ct) do
        call_cmd!(
          Commands::Container::Copy,
          **opts.merge(consistent: true, restart: false)
        )

        if state == :running
          call_cmd!(
            Commands::Container::Start,
            id: opts[:target_id],
            pool: opts[:target_pool] || ct.pool.name,
            force: true
          )
        end

        call_cmd!(
          Commands::Container::Delete,
          id: opts[:id],
          pool: opts[:pool],
          force: true
        )
      end
    end
  end
end
