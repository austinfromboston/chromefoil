require 'capybara'

lib = File.expand_path('../..', __FILE__)
$:.unshift lib unless $:.include?(lib)

module Capybara
  module Chromefoil
    require 'capybara/chromefoil/browser'
    require 'capybara/chromefoil/chrome_client'
    require 'capybara/chromefoil/command'
    require 'capybara/chromefoil/dev_tools_client'
    require 'capybara/chromefoil/driver'
    require 'capybara/chromefoil/errors'
    require 'capybara/chromefoil/node'
    require 'capybara/chromefoil/web_socket_client'
  end
end

Capybara.register_driver :chromefoil do |app|
  Capybara::Chromefoil::Driver.new(app)
end
