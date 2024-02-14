module OsCtld
  module Utils::Ip
    # @return [OsCtl::Lib::SystemCommandResult]
    def ip(ip_v, args, **opts)
      cmd = ['ip']

      case ip_v
      when 4
        cmd << '-4'
      when 6
        cmd << '-6'
      when :all
        # nothing to do
      else
        raise "unknown IP version '#{ip_v}'"
      end

      cmd.concat(args)
      syscmd(cmd.join(' '), opts)
    end

    # @return [OsCtl::Lib::SystemCommandResult]
    def tc(args, **opts)
      cmd = ['tc'].concat(args)
      syscmd(cmd.join(' '), opts)
    end
  end
end
