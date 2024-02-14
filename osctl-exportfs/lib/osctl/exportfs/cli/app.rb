require 'gli'

module OsCtl::ExportFS::Cli
  class App
    include GLI::App

    def self.run
      cli = new
      cli.setup
      exit(cli.run(ARGV))
    end

    def setup
      Thread.abort_on_exception = true

      program_desc 'Manage dedicated NFS servers for filesystem exports'
      version OsCtl::ExportFS::VERSION
      subcommand_option_handling :normal
      preserve_argv true
      arguments :strict

      desc 'Manage NFS servers'
      command :server do |srv|
        srv.desc 'List configured NFS server'
        srv.arg_name '<name>'
        srv.command :ls do |c|
          c.desc 'Select parameters to output'
          c.flag %i[o output], arg_name: 'parameters'

          c.desc 'Do not show header'
          c.switch %i[H hide-header], negatable: false

          c.desc 'List available parameters'
          c.switch %i[L list], negatable: false

          c.desc 'Sort by parameter(s)'
          c.flag %i[s sort], arg_name: 'parameters'

          c.action(&Command.run(Server, :list))
        end

        srv.desc 'Create a new NFS server'
        srv.arg_name '<name>'
        srv.command :new do |c|
          c.desc 'Listen on address'
          c.flag %i[a address], arg_name: 'address'

          c.desc 'Host network interface name'
          c.flag :netif, arg_name: 'netif'

          c.desc 'Configure port for rpc.nfsd'
          c.flag 'nfsd-port', arg_name: 'port', type: Integer

          c.desc 'Configure the number of NFS server threads'
          c.flag 'nfsd-nproc', arg_name: 'nproc', type: Integer

          c.desc 'Open and listen on a TCP socket'
          c.switch 'nfsd-tcp', default_value: true

          c.desc 'Open and listen on a UDP socket'
          c.switch 'nfsd-udp', default_value: false

          c.desc 'Select supported NFS versions'
          c.flag 'nfs-versions', default_value: '3'

          c.desc 'Direct messages from rpc.nfsd to syslog'
          c.switch 'nfsd-syslog', default_value: false

          c.desc 'Configure port for rpc.mountd'
          c.flag 'mountd-port', arg_name: 'port', type: Integer

          c.desc 'Configure port for lockd'
          c.flag 'lockd-port', arg_name: 'port', type: Integer

          c.desc 'Configure port for rpc.statd'
          c.flag 'statd-port', arg_name: 'port', type: Integer

          c.action(&Command.run(Server, :create))
        end

        srv.desc 'Delete NFS server'
        srv.arg_name '<name>'
        srv.command :del do |c|
          c.action(&Command.run(Server, :delete))
        end

        srv.desc 'Configure NFS server'
        srv.arg_name '<name>'
        srv.command :set do |c|
          c.desc 'Listen on address'
          c.flag %i[a address], arg_name: 'address'

          c.desc 'Host network interface name'
          c.flag :netif, arg_name: 'netif'

          c.desc 'Configure port for rpc.nfsd'
          c.flag 'nfsd-port', arg_name: 'port', type: Integer

          c.desc 'Configure the number of NFS server threads'
          c.flag 'nfsd-nproc', arg_name: 'nproc', type: Integer

          c.desc 'Open and listen on a TCP socket'
          c.switch 'nfsd-tcp', default_value: true

          c.desc 'Open and listen on a UDP socket'
          c.switch 'nfsd-udp', default_value: false

          c.desc 'Select supported NFS versions'
          c.flag 'nfs-versions'

          c.desc 'Direct messages from rpc.nfsd to syslog'
          c.switch 'nfsd-syslog', default_value: false

          c.desc 'Configure port for rpc.mountd'
          c.flag 'mountd-port', arg_name: 'port', type: Integer

          c.desc 'Configure port for lockd'
          c.flag 'lockd-port', arg_name: 'port', type: Integer

          c.desc 'Configure port for rpc.statd'
          c.flag 'statd-port', arg_name: 'port', type: Integer

          c.action(&Command.run(Server, :set))
        end

        srv.desc 'Start NFS server'
        srv.arg_name '<name>'
        srv.command :start do |c|
          c.action(&Command.run(Server, :start))
        end

        srv.desc 'Stop NFS server'
        srv.arg_name '<name>'
        srv.command :stop do |c|
          c.action(&Command.run(Server, :stop))
        end

        srv.desc 'Restart NFS server'
        srv.arg_name '<name>'
        srv.command :restart do |c|
          c.action(&Command.run(Server, :restart))
        end

        srv.desc 'Run NFS server'
        srv.arg_name '<name>'
        srv.command :spawn do |c|
          c.action(&Command.run(Server, :spawn))
        end

        srv.desc 'Run shell in NFS server container'
        srv.arg_name '<name>'
        srv.command :attach do |c|
          c.action(&Command.run(Server, :attach))
        end
      end

      desc 'Manage exported filesystems'
      command :export do |exp|
        exp.desc 'List exported filesystems'
        exp.arg_name '[server]'
        exp.command :ls do |c|
          c.action(&Command.run(Export, :list))
        end

        exp.desc 'Export filesystem'
        exp.arg_name '<server>'
        exp.command :add do |c|
          c.desc 'Directory to export'
          c.flag %w[d directory], required: true

          c.desc 'Export the directory as'
          c.flag %w[a as]

          c.desc 'Mask for allowed hosts'
          c.flag %w[h host], default_value: '*'

          c.desc 'Options'
          c.flag %w[o options], default_value: 'rw,no_subtree_check,no_root_squash'

          c.action(&Command.run(Export, :add))
        end

        exp.desc 'Unexport filesystem'
        exp.arg_name '<server>'
        exp.command :del do |c|
          c.desc 'Directory to unexport'
          c.flag %w[a as], required: true

          c.desc 'Mask for allowed hosts'
          c.flag %w[h host], default_value: '*'

          c.action(&Command.run(Export, :remove))
        end
      end
    end
  end
end
