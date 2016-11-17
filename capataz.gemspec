# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capataz/version'

Gem::Specification.new do |spec|
  spec.name          = 'capataz'
  spec.version       = Capataz::VERSION
  spec.authors       = ['Maikel Arcia']
  spec.email         = ['macarci@gmail.com']

  spec.summary       = %q{Provides Ruby code execution control by defining rules for syntax and runtime behavior.}
  spec.homepage      = 'https://github.com/macarci/capataz'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.8'
  spec.add_development_dependency 'rake', '~> 10.0'

  spec.add_runtime_dependency 'parser'
end
