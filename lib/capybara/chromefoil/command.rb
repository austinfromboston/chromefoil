module Capybara::Chromefoil
  class Command
    attr_reader :id
    attr_reader :method
    attr_accessor :params

    def self.next_command_id
      @last_id ||= 0
      @last_id += 1
    end

    def initialize(method, params={})
      @id = Command.next_command_id
      @method= method
      @params = params
    end

    def message
      JSON.dump({ 'id' => @id, 'method' => @method, 'params' => @params })
    end
  end
end
