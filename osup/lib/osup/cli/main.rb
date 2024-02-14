require 'libosctl'

module OsUp
  class Cli::Main < Cli::Command
    include OsCtl::Lib::Utils::Log
    include OsCtl::Lib::Utils::System

    def status
      require_args!(optional: %w[pool])

      if args[0]
        pool_status(args[0])

      else
        global_status
      end
    end

    def check
      require_args!(optional: %w[pool])

      if args[0]
        pool_check(args[0])

      else
        global_check
      end
    end

    def check_rollback
      require_args!('pool', 'version')
      puts pool_flags_rollback(PoolMigrations.new(args[0]), args[1].to_i)
    end

    def init
      require_args!('pool')

      OsUp.init(args[0], force: opts[:force])
    end

    def upgrade
      require_args!('pool', optional: %w[version])

      OsUp.upgrade(
        args[0],
        to: args[1] && args[1].to_i,
        dry_run: gopts['dry-run']
      )
    rescue PoolUpToDate => e
      puts e.message
    end

    def upgrade_all
      require_args!(optional: %w[version])

      target = args[0] && args[0].to_i

      active_pools.each do |pool|
        pool_migrations = PoolMigrations.new(pool)

        begin
          OsUp.upgrade(pool, version: target, dry_run: gops['dry-run'])
        rescue PoolUpToDate
          next
        rescue RuntimeError => e
          warn e.message
          next
        end
      end
    end

    def rollback
      require_args!('pool', optional: %w[version])

      OsUp.rollback(
        args[0],
        to: args[1] && args[1].to_i,
        dry_run: gopts['dry-run']
      )
    end

    def rollback_all
      require_args!(optional: %w[version])

      target = args[0] && args[0].to_i

      active_pools.each do |pool|
        OsUp.rollback(pool, to: target, dry_run: gopts['dry-run'])
      rescue RuntimeError => e
        warn e.message
        next
      end
    end

    def gen_bash_completion
      c = OsCtl::Lib::Cli::Completion::Bash.new(Cli::App.get)
      puts c.generate
    end

    protected

    def global_status
      unless opts['hide-header']
        puts format(
          '%-15s %-12s %10s %10s %10s',
          'POOL', 'STATUS', 'MIGRATIONS', 'UP', 'DOWN'
        )
      end

      active_pools.each do |pool|
        pool_migrations = PoolMigrations.new(pool)

        total = pool_migrations.all.count
        up = pool_migrations.all.count { |_id, m| m ? pool_migrations.applied?(m) : true }
        down = total - up

        puts format(
          '%-15s %-12s %10d %10d %10d',
          pool,
          pool_state(pool_migrations),
          total,
          up,
          down
        )
      end
    end

    def pool_status(pool)
      pool_migrations = PoolMigrations.new(pool)

      unless opts['hide-header']
        puts format(
          '%-20s %-10s  %s',
          'MIGRATION', 'STATUS', 'NAME'
        )
      end

      pool_migrations.all.each do |id, m|
        puts format(
          '%-20d %-10s  %s',
          id,
          if m
            pool_migrations.applied?(m) ? 'up' : 'down'
          else
            'up'
          end,
          m ? m.name : '** migration not found **'
        )
      end
    end

    def global_check
      active_pools.each { |pool| pool_check(pool) }
    end

    def pool_check(pool)
      pool_migrations = PoolMigrations.new(pool)
      state = pool_state(pool_migrations)

      puts format(
        '%-15s %-15s %-15s %s',
        pool,
        state,
        MigrationList.get.last.id,
        state == 'outdated' ? pool_flags_upgrade(pool_migrations) : '-'
      )
    end

    def active_pools
      ret = []

      zfs(
        :list,
        '-r -d0 -H -o name,org.vpsadminos.osctl:active', ''
      ).output.strip.split("\n").each do |line|
        pool, active = line.split
        ret << pool if active == 'yes'
      end

      ret
    end

    def pool_state(pool_migrations)
      if !pool_migrations.upgradable?
        'incompatible'

      elsif pool_migrations.uptodate?
        'ok'

      else
        'outdated'
      end
    end

    def pool_flags_upgrade(pool_migrations)
      pool_flags(OsUp::Migrator.upgrade_sequence(pool_migrations))
    end

    def pool_flags_rollback(pool_migrations, version)
      pool_flags(OsUp::Migrator.rollback_sequence(pool_migrations, to: version))
    end

    def pool_flags(sequence)
      flags = []

      all_not_export = sequence.all? { |m| !m.export_pool }
      flags << 'export' unless all_not_export

      all_not_stop = sequence.all? { |m| !m.stop_containers }
      flags << 'stop' unless all_not_stop

      flags.any? ? flags.join(',') : '-'
    end
  end
end
