require 'libosctl'
require 'etc'

module OsCtld
  class AutoStop::Plan
    include OsCtl::Lib::Utils::Log

    attr_reader :pool

    def initialize(pool)
      @pool = pool
      @plan = ContinuousExecutor.new(pool.parallel_stop)
      @stop = false
      @nproc = Etc.nprocessors
    end

    # Stop all containers on pool
    #
    # It is assumed that manipulation lock is held on all containers on the pool.
    #
    # @param message [String]
    # @param client_handler [Generic::ClientHandler, nil]
    def start(message: nil, client_handler: nil)
      @stop = false

      log(
        :info,
        "Auto-stopping containers, #{pool.parallel_stop} containers at a time"
      )

      # Sort containers by reversed autostart priority -- containers with
      # the lowest priority are stopped first
      cts = DB::Containers.get.select { |ct| ct.pool == pool }

      log(:info, "#{cts.size} containers to stop")

      if CpuScheduler.use_sequential_start_stop?
        log(:info, 'Using sequential auto-stop')

        cts.sort! do |a, b|
          a_conf = a.run_conf
          b_conf = b.run_conf

          # rubocop:disable Lint/DuplicateBranch
          #
          # Stop running containers first
          if a_conf && !b_conf
            -1
          elsif !a_conf && b_conf
            1
          elsif !a_conf && !b_conf
            0

          # Stop containers with a CPU package first
          elsif a_conf.cpu_package && !b_conf.cpu_package
            -1
          elsif !a_conf.cpu_package && b_conf.cpu_package
            1
          elsif !a_conf.cpu_package && !b_conf.cpu_package
            0

          # Same CPU package, sort by autostart priority
          elsif a_conf.cpu_package == b_conf.cpu_package
            if a.autostart && b.autostart
              b.autostart <=> a.autostart
            elsif a.autostart
              1
            elsif b.autostart
              -1
            else
              0
            end

          # Sort by CPU package, lower package first
          else
            a_conf.cpu_package <=> b_conf.cpu_package
          end

          # rubocop:enable Lint/DuplicateBranch
        end
      else
        log(:info, 'Using priority auto-stop')

        cts.sort! do |a, b|
          if a.autostart && b.autostart
            b.autostart <=> a.autostart
          elsif a.autostart
            1
          elsif b.autostart
            -1
          else
            0
          end
        end
      end

      # Progress counters
      total = cts.count
      done = 0
      mutex = Mutex.new
      debug = Daemon.get.config.debug?

      # Stop the containers
      cmds = cts.each_with_index.map do |ct, i|
        if debug
          run_conf = ct.run_conf

          log(
            :debug,
            "[#{(i + 1).to_s.rjust(4)}/#{total}] #{ct.id} priority=#{ct.autostart ? ct.autostart.priority : '-'} cpu-package=#{run_conf ? run_conf.cpu_package : '-'}"
          )
        end

        ContinuousExecutor::Command.new(id: ct.id, priority: i) do |_cmd|
          if client_handler
            mutex.synchronize do
              done += 1
              client_handler.send_update(
                "[#{done}/#{total}] " +
                (ct.ephemeral? ? 'Deleting ephemeral container' : 'Stopping container') +
                " #{ct.ident}"
              )
            end
          end

          log(:info, ct, 'Auto-stopping container')
          do_stop_ct(ct, message:)
        end
      end

      plan << cmds
    end

    def clear
      plan.clear
    end

    def resize(new_size)
      plan.resize(new_size)
    end

    def wait
      plan.wait_until_empty
    end

    def stop
      @stop = true
      plan.stop
    end

    def queue
      plan.queue
    end

    def log_type
      "#{pool.name}:auto-stop"
    end

    protected

    attr_reader :plan

    def do_stop_ct(ct, message: nil)
      if ct.ephemeral?
        Commands::Container::Delete.run(
          pool: pool.name,
          id: ct.id,
          force: true,
          progress: false,
          manipulation_lock: 'ignore',
          message:
        )
      else
        Commands::Container::Stop.run(
          pool: pool.name,
          id: ct.id,
          progress: false,
          manipulation_lock: 'ignore',
          message:
        )

        pool.autostart_plan.clear_ct(ct)
      end
    end

    def stop?
      @stop
    end
  end
end
