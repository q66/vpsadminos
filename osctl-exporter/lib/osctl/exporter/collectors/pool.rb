require 'osctl/exporter/collectors/base'

module OsCtl::Exporter
  class Collectors::Pool < Collectors::Base
    def setup
      add_metric(
        :pools,
        :gauge,
        :osctl_pool_count,
        docstring: 'Number of imported pools',
        labels: [:state]
      )

      add_metric(
        :pool_containers,
        :gauge,
        :osctl_pool_containers_count,
        docstring: 'Number of pool containers',
        labels: %i[pool state]
      )
    end

    def collect(client)
      collect_pools(client)
      collect_pool_containers(client)
    end

    protected

    attr_reader :pools, :pool_containers

    def collect_pools(client)
      states = {
        importing: 0,
        active: 0,
        disabled: 0
      }

      client.list_pools.each do |pool|
        st = pool[:state].to_sym

        unless states.has_key?(st)
          log(:warn, "Pool #{pool[:name]} is in invalid state '#{st}'")
          next
        end

        states[st] += 1
      end

      states.each do |st, cnt|
        pools.set(cnt, labels: { state: st })
      end
    end

    def collect_pool_containers(client)
      pools = client.list_pools
      pool_cts = {}

      pools.each do |pool|
        pool_cts[pool[:name]] = {
          staged: 0,
          stopped: 0,
          starting: 0,
          running: 0,
          stopping: 0,
          freezing: 0,
          frozen: 0,
          thawed: 0,
          aborting: 0,
          error: 0
        }
      end

      client.list_containers.each do |ct|
        pool = ct[:pool]
        st = ct[:state].to_sym

        next if !pool_cts.has_key?(pool) || !pool_cts[pool].has_key?(st)

        pool_cts[pool][st] += 1
      end

      pool_cts.each do |pool, states|
        states.each do |st, cnt|
          pool_containers.set(cnt, labels: { pool:, state: st })
        end
      end
    end
  end
end
