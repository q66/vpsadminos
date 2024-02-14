require 'osctld/commands/logged'

module OsCtld
  class Commands::Container::MountDataset < Commands::Logged
    handle :ct_mount_dataset

    def find
      ct = DB::Containers.find(opts[:id], opts[:pool])
      ct || error!('container not found')
    end

    def execute(ct)
      manipulate(ct) do
        ds = OsCtl::Lib::Zfs::Dataset.new(
          File.join(ct.dataset.name, opts[:name]),
          base: ct.dataset.name
        )
        error!("dataset #{ds.name} does not exist") unless ds.exist?

        m_opts = %w[bind create=dir]
        m_opts << opts[:mode]

        mnt = Mount::Entry.new(
          nil,
          opts[:mountpoint],
          'bind',
          m_opts.join(','),
          opts[:automount],
          dataset: ds
        )

        if ct.mounts.find_at(mnt.mountpoint)
          next error("mountpoint '#{mnt.mountpoint}' is already mounted")
        end

        ct.mounts.add(mnt)
        ok
      end
    end
  end
end
