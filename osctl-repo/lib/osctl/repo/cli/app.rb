require 'gli'
require 'thread'

module OsCtl::Repo::Cli
  class App
    include GLI::App

    def self.run
      cli = new
      cli.setup
      exit(cli.run(ARGV))
    end

    def setup
      Thread.abort_on_exception = true

      program_desc 'Create and use vpsAdminOS image repositories'
      version OsCtl::Repo::VERSION
      subcommand_option_handling :normal
      preserve_argv true
      arguments :strict

      desc 'Create and manage a local repository'
      command :local do |local|
        local.desc 'Create a new empty repository in the current directory'
        local.command :init do |c|
          c.action(&Command.run(Repo, :init))
        end

        local.desc 'List images'
        local.command %i[ls list] do |c|
          c.action(&Command.run(Repo, :local_list))
        end

        local.desc 'Add file into the repository'
        local.arg_name '<vendor> <variant> <arch> <distribution> <version>'
        local.command :add do |c|
          c.desc 'Tag'
          c.flag :tag, multiple: true

          c.desc 'Image with rootfs archive'
          c.flag :archive

          c.desc 'Image with rootfs stream'
          c.flag :stream

          c.action(&Command.run(Repo, :add))
        end

        local.desc 'Access images from the repository'
        local.command :get do |get|
          get.desc 'Get path to an image inside the repository'
          get.arg_name '<vendor> <variant> <arch> <distribution> <version> tar|zfs'
          get.command :path do |c|
            c.action(&Command.run(Repo, :local_get_path))
          end
        end

        local.desc "Set default vendor or default vendor's variant"
        local.arg_name '<vendor> [variant]'
        local.command :default do |c|
          c.action(&Command.run(Repo, :set_default))
        end

        local.desc 'Remove image from the repository'
        local.arg_name '<vendor> <variant> <arch> <distribution> <version>'
        local.command :rm do |c|
          c.action(&Command.run(Repo, :rm))
        end
      end

      desc 'Interact with remote repositories'
      command :remote do |remote|
        remote.desc 'List available images'
        remote.arg_name '<repo>'
        remote.command %i[ls list] do |c|
          c.desc 'Cache directory'
          c.flag :cache

          c.action(&Command.run(Repo, :remote_list))
        end

        remote.desc 'Fetch file from the repository and store it in a local cache'
        remote.arg_name '<repo> <vendor> <variant> <arch> <distribution> <version>|<tag> tar|zfs'
        remote.command :fetch do |c|
          c.desc 'Cache directory'
          c.flag :cache, required: true

          c.action(&Command.run(Repo, :fetch))
        end

        remote.desc 'Get a file from the repository'
        remote.command :get do |get|
          get.desc 'Get path to cached image'
          get.arg_name '<repo> <vendor> <variant> <arch> <distribution> <version>|<tag> tar|zfs'
          get.command :path do |c|
            c.desc 'Cache directory'
            c.flag :cache, required: true

            c.desc 'Force remote repository check'
            c.switch 'force-check', default_value: false

            c.action(&Command.run(Repo, :remote_get_path))
          end

          get.desc 'Dump image to stdout'
          get.arg_name '<repo> <vendor> <variant> <arch> <distribution> <version>|<tag> tar|zfs'
          get.command :stream do |c|
            c.desc 'Cache directory'
            c.flag :cache

            c.desc 'Force remote repository check'
            c.switch 'force-check', default_value: false

            c.action(&Command.run(Repo, :remote_get_stream))
          end
        end
      end
    end
  end
end
