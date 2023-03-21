lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'osctld/version'

Gem::Specification.new do |s|
  s.name        = 'osctld'

  if ENV['OS_BUILD_ID']
    s.version   = "#{OsCtld::VERSION}.build#{ENV['OS_BUILD_ID']}"
  else
    s.version   = OsCtld::VERSION
  end

  s.summary       =
  s.description   = 'Management daemon for vpsAdminOS'
  s.authors       = 'Jakub Skokan'
  s.email         = 'jakub.skokan@vpsfree.cz'
  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.extensions   << 'ext/osctld/extconf.rb'
  s.require_paths = ['lib', 'ext']
  s.license       = 'Apache-2.0'

  s.required_ruby_version = '>= 2.0.0'

  s.add_runtime_dependency 'bindata', '~> 2.4.15'
  s.add_runtime_dependency 'concurrent-ruby', '~> 1.1.9'
  s.add_runtime_dependency 'json'
  s.add_runtime_dependency 'ipaddress', '~> 0.8.3'
  s.add_runtime_dependency 'libosctl', s.version
  s.add_runtime_dependency 'netlinkrb', '0.18.vpsadminos.0'
  s.add_runtime_dependency 'osctl-repo', s.version
  s.add_runtime_dependency 'osup', s.version
  s.add_runtime_dependency 'require_all', '~> 2.0.0'
  s.add_runtime_dependency 'ruby-lxc', '1.2.4.vpsadminos.3'
  s.add_development_dependency 'rake'
  s.add_development_dependency 'rake-compiler'
  s.add_development_dependency 'yard'
end
