module Capybara::Chromefoil
  class DevToolsClient

    attr_reader :socket, :fixed_port, :timeout, :custom_host

    def initialize(fixed_port = nil, timeout = nil, custom_host = nil)
      @fixed_port = fixed_port
      @timeout    = timeout
      @custom_host = custom_host
      start
    end

    def port
      @socket.port
    end

    def host
      @socket.host
    end

    def timeout=(sec)
      @timeout = sec
    end

    def start
      @socket = Capybara::Chromefoil::WebSocketClient.new host: custom_host, port: fixed_port
    end

    def stop
      @socket.ws.close
    end

    def restart
      stop
      start
    end

    def send(command)
      @socket.send_message(command.id, command.message)# or raise DeadClient.new(command.message)
    end
  end
end
