# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ar_state_machine/version'

Gem::Specification.new do |spec|
  spec.name          = "ar_state_machine"
  spec.version       = ARStateMachine::VERSION
  spec.authors       = ["Casey Juan Lopez", "Kevin Solkowski", "Austin Kahly"]
  spec.email         = ["casey@wantable.com"]

  spec.summary       = %q{A state machine}
  spec.description   = %q{A state machine built on top of the Active Record callback chain.}
  spec.homepage      = "https://github.com/wantable/ar_state_machine"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against public gem pushes."
  end

  spec.license       = 'MIT'
  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency('rspec')
  spec.add_dependency "activerecord", ">= 5.2"
  spec.add_dependency "timecop"
end
