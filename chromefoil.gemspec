lib = File.expand_path('../lib/', __FILE__)
$:.unshift lib unless $:.include?(lib)

require 'chromefoil/version'

Gem::Specification.new do |spec|
  spec.name        = 'chromefoil'
  spec.version     = Chromefoil::VERSION
  spec.summary     = "A Ruby wrapper for the Chrome DevTools API"
  spec.description = "A Ruby wrapper for the Chrome DevTools API"
  spec.authors     = ["Austin Putman"]
  spec.email       = 'austin@rawfingertips.com'
  spec.files       = Dir.glob('{lib}/**/*')
  spec.homepage    =
    'https://rubygems.org/gems/chromefoil'
  spec.license       = 'MIT'
  spec.executables << 'chromefoil'

  spec.add_runtime_dependency 'capybara'
  spec.add_development_dependency 'minitest-rg'
  spec.add_development_dependency 'celluloid-websocket-client'
end
