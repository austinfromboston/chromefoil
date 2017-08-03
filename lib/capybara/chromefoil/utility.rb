# full credit: teampoltergeist

module Capybara
  module Chromefoil
    class << self
      def windows?
        RbConfig::CONFIG["host_os"] =~ /mingw|mswin|cygwin/
      end

      def mri?
        defined?(RUBY_ENGINE) && RUBY_ENGINE == "ruby"
      end
    end
  end
end
