require 'libosctl'
require 'osctld/dist_config/distributions/base'

module OsCtld
  class DistConfig::Distributions::Other < DistConfig::Distributions::Base
    distribution :other

    include OsCtl::Lib::Utils::Log

    def configurator_class
      DistConfig::Configurator
    end

    def set_hostname(_opts = {})
      log(
        :warn,
        ct,
        "Unable to set hostname: #{ctrc.distribution} not supported"
      )
    end

    def network(_opts = {})
      log(
        :warn,
        ct,
        "Unable to configure network: #{ctrc.distribution} not supported"
      )
    end
  end
end
