require 'pry'
require 'osvm'

module TestRunner
  class TestEvaluator
    attr_reader :machines

    # @param test [Test]
    # @param opts [Hash]
    # @option opts [Integer] :default_timeout
    # @option opts [Boolean] :destructive
    # @option opts [String] :state_dir
    # @option opts [String] :sock_dir
    def initialize(test, **opts)
      @test = test
      @config = TestConfig.build(test)
      @opts = opts
      @machines = {}

      config[:machines].each do |name, cfg|
        var = :"@#{name}"
        m = OsVm::Machine.new(
          name,
          OsVm::MachineConfig.new(cfg),
          opts[:state_dir],
          opts[:sock_dir],
          default_timeout: opts[:default_timeout],
          hash_base: test.path
        )
        instance_variable_set(var, m)

        define_singleton_method(name) do
          instance_variable_get(var)
        end

        machines[name] = m
      end
    end

    # Run the test script
    def run
      do_run do
        test_script
      end
    end

    # Run interactive shell
    def interactive
      do_run do
        binding.pry # rubocop:disable Lint/Debugger
      end
    end

    # Start all machines
    def start_all
      machines.each(&:start)
    end

    # Invoke interactive shell from within a test
    def breakpoint
      binding.pry # rubocop:disable Lint/Debugger
    end

    protected

    attr_reader :test, :config, :opts

    def test_script
      binding.eval(config[:testScript])
    end

    def do_run
      yield
    ensure
      machines.each_value do |m|
        m.kill
        m.destroy if opts[:destructive]
        m.finalize
        m.cleanup
      end
    end
  end
end
