require 'json'
require 'osctl/repo/cli/command'

module OsCtl::Repo
  class Cli::Repo < Cli::Command
    def init
      repo = Local::Repository.new(Dir.pwd)
      raise 'repository already exists' if repo.exist?

      repo.create
    end

    def local_list
      repo = Local::Repository.new(Dir.pwd)
      raise 'repository not found' unless repo.exist?

      fmt = '%-18s %-18s %-10s %-20s %-10s %s'

      puts format(
        fmt,
        'VENDOR', 'VARIANT', 'ARCH', 'DISTRIBUTION', 'VERSION', 'TAGS'
      )

      repo.images.each do |t|
        puts format(
          fmt,
          t.vendor,
          t.variant,
          t.arch,
          t.distribution,
          t.version,
          t.tags.join(',')
        )
      end
    end

    def add
      require_args!('vendor', 'variant', 'arch', 'distribution', 'version')

      repo = Local::Repository.new(Dir.pwd)
      raise 'repository not found' unless repo.exist?

      vendor, variant, arch, distribution, version = args

      if vendor == 'default'
        raise GLI::BadCommandLine, 'unable to set vendor to default, name reserved'

      elsif variant == 'default'
        raise GLI::BadCommandLine, 'unable to set variant to default, name reserved'
      end

      image = {
        tar: opts[:archive],
        zfs: opts[:stream]
      }.select { |_, v| v }.to_h

      if image.empty?
        raise GLI::BadCommandLine, 'no image, use --archive or --stream'
      end

      repo.add(
        vendor,
        variant,
        arch,
        distribution,
        version,
        tags: opts[:tag],
        image:
      )
    end

    def local_get_path
      require_args!(
        'vendor', 'variant', 'arch', 'distribution', 'version|tag', 'tar|zfs'
      )

      repo = Local::Repository.new(Dir.pwd)
      raise 'repository not found' unless repo.exist?

      vendor, variant, arch, distribution, version, format = args
      img = repo.find(vendor, variant, arch, distribution, version)
      raise 'image not found' unless img
      raise 'image format not found' unless img.has_image?(format)

      puts img.version_image_path(format)
    end

    def set_default
      require_args!('vendor', optional: %w[variant])

      repo = Local::Repository.new(Dir.pwd)
      raise 'repository not found' unless repo.exist?

      if args.count == 1
        repo.set_default_vendor(args[0])

      elsif args.count == 2
        repo.set_default_variant(args[0], args[1])

      else
        raise GLI::BadCommandLine, 'too many aguments'
      end
    end

    def rm
      require_args!('vendor', 'variant', 'arch', 'distribution', 'version')

      repo = Local::Repository.new(Dir.pwd)
      raise 'repository not found' unless repo.exist?

      tpl = repo.find(*args)
      raise 'image not found' unless tpl

      repo.remove(tpl)
    end

    def remote_list
      require_args!('repo')

      repo = Remote::Repository.new(args[0])

      if opts[:cache]
        repo.path = opts[:cache]
        dl = Downloader::Cached.new(repo)
      else
        dl = Downloader::Direct.new(repo)
      end

      puts dl.list.map(&:dump).to_json
    end

    def fetch
      require_args!(
        'repo', 'vendor', 'variant', 'arch', 'distribution', 'version|tag',
        'tar|zfs'
      )

      repo = Remote::Repository.new(args[0])
      repo.path = opts[:cache]

      dl = Downloader::Cached.new(repo)
      puts dl.get(*args[1..-1], force_check: true)
    end

    def remote_get_path
      dl = remote_get_common
      puts dl.get(*args[1..-1], force_check: opts['force-check'])
    end

    def remote_get_stream
      dl = remote_get_common
      dl.get(*args[1..-1], force_check: opts['force-check']) do |fragment|
        $stdout.write(fragment)
      end
    end

    protected

    def remote_get_common
      require_args!(
        'repo', 'vendor', 'variant', 'arch', 'distribution', 'version|tag',
        'tar|zfs'
      )

      repo = Remote::Repository.new(args[0])

      if opts[:cache]
        repo.path = opts[:cache]
        Downloader::Cached.new(repo)
      else
        Downloader::Direct.new(repo)
      end
    end
  end
end
