require "net/http"
require "uri"
require 'json'
require 'timeout'
require 'websocket-client-simple'

module Capybara::Chromefoil
  class WsClientWrapper < WebSocket::Client::Simple::Client
    attr_accessor :results, :commands

    def self.connect(url, options={})
      client = new
      yield client if block_given?
      client.connect url, options
      return client
    end

    def initialize(*args)
      @commands = {}
      @results = {}
      super
    end
  end

  class WebSocketClient
    attr_reader :host, :port, :uri, :timeout
    attr_accessor :tabs, :ws

    def initialize( host:, port:, timeout: 10)
      @host = host || "localhost"
      @port = port || 9222
      @timeout = timeout || 10
    end

    def base_endpoint_url
      "http://#{host}:#{port}/json"
    end

    def tab_ws_url(tab_index)
      uri = URI.parse(base_endpoint_url)
      response = Net::HTTP.get_response(uri)
      self.tabs = JSON.parse(response.body).select do |tab_data|
        tab_data['type'] == "page"
      end
      tabs[tab_index]['webSocketDebuggerUrl']
    rescue Errno::ECONNREFUSED
      p "browser not yet ready, retrying"
      sleep 0.5
      retry
    end

    def connect(tab_index: 0)
      if(self.ws == nil)
        self.ws = WsClientWrapper.connect tab_ws_url(tab_index)

        ws.on :message do |msg|
          puts msg.data
          data = JSON.parse(msg.data)
          if data.has_key? 'id'
            results[data['id']] << msg.data
          end
        end

        ws.on :open do
          p "opened"
        end

        ws.on :close do |e|
          p "closed"
          p e
          #exit 1
        end

        ws.on :error do |e|
          p "error received"
          p e
        end
      end

      yield ws if block_given?
    end

    def send_message(command_id, message, await_result=true)
      connect do |ws|
        ws.commands[command_id] = message
        ws.results[command_id] = []
        p "sending #{message}"
        ws.send message
        Timeout.timeout(timeout) do
          while ws.results[command_id].length == 0 do
            sleep 0.05
          end
          return ws.results[command_id].last
          #ws.close
        end
      end
    end
  end
end
