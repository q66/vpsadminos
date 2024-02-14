require 'osctld/commands/base'

module OsCtld
  class Commands::Container::CGParamApply < Commands::Base
    handle :ct_cgparam_apply

    include OsCtl::Lib::Utils::Log
    include Utils::CGroupParams

    def execute
      ct = DB::Containers.find(opts[:id], opts[:pool])
      return error('container not found') unless ct

      log(:info, ct, 'Configuring cgroups')

      ret = call_cmd(Commands::Group::CGParamApply, name: ct.group.name, pool: ct.pool.name)
      return ret unless ret[:status]

      apply(ct, force: ct.running?)

      ok
    end
  end
end
