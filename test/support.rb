require 'minitest/autorun'
require "minitest/rg"
require 'chromefoil'

module Minitest
  class Spec
    module DSL
      def context(*args, &blk)
        send :describe, *args, &blk
      end
    end
  end
end
