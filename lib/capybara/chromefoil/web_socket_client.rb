require "net/http"
require "uri"
require 'json'
require 'timeout'
require 'websocket-client-simple'

module Capybara::Chromefoil
  class WsClientWrapper < WebSocket::Client::Simple::Client
    attr_accessor :results, :commands, :events
    HANDLERS = {
      "Network.responseReceived" => :network_response_received
    }

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

    def call_handler(data)
      #if data['method'] !~ /Network\.|DOM\./
      if data['method'] !~ /Network\./
        puts "Received: #{data}"
      end
      return unless HANDLERS[data['method']]
      __send__ HANDLERS[data['method']], data['params']
    end

    def last_page_load_command_id
      last_loaded_page = commands.to_a.reverse.find do |(_, msg)|
        msg =~ /Page.navigate/
      end
      last_loaded_page[0] if last_loaded_page
    end

    def network_response_received(params)
      response_request = params.fetch('requestId')
      response_frame = params.fetch('frameId')
      return unless response_request && response_request == response_frame

      related_result = results[last_page_load_command_id]&.last || {}

      if related_result.fetch('result', {}).fetch('frameId') == response_frame
        results[last_page_load_command_id] << params
      end
    end
  end

  class WebSocketClient
    attr_reader :host, :port, :uri, :timeout, :current_tab
    attr_accessor :tabs, :ws

    def initialize( host:, port:, timeout: 10)
      @host = host || "localhost"
      @port = port || 9222
      @timeout = timeout || 10
    end

    def base_endpoint_url
      "http://#{host}:#{port}/json"
    end

    def current_url
      current_tab_id = current_tab['id']
      refresh_tabs
      tabs.find { |t| t['id'] == current_tab_id }['url']
    end

    def current_page_title
      current_tab_id = current_tab['id']
      refresh_tabs
      tabs.find { |t| t['id'] == current_tab_id }['title']
    end

    def last_status_code
      ws.results[ws.last_page_load_command_id].last.fetch('response', {}).fetch('status')
    end

    def tab_ws_url(tab_index)
      refresh_tabs
      tabs[tab_index]['webSocketDebuggerUrl']
    end

    def refresh_tabs
      uri = URI.parse(base_endpoint_url)
      response = Net::HTTP.get_response(uri)
      self.tabs = JSON.parse(response.body).select do |tab_data|
        tab_data['type'] == "page"
      end
    rescue Errno::ECONNREFUSED
      p "browser not yet ready, retrying"
      sleep 0.5
      retry
    end

    def connect(tab_index: 0)
      if(self.ws == nil)
        self.ws = WsClientWrapper.connect tab_ws_url(tab_index)
        @current_tab = tabs[tab_index]

        ws.on :message do |msg|
          data = JSON.parse(msg.data)
          if data.has_key? 'id'
            results[data['id']] << data
            p msg.data
          elsif data.has_key? 'method'
            call_handler(data)
          end
        end

        ws.on :open do
          p "opened"
        end

        ws.on :close do |e|
          p "closed"
          p e.to_s
          #exit 1
        end

        ws.on :error do |e|
          p "error received"
          p e.to_s
        end

        while !ws.open?
          sleep 0.1
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
          return JSON.dump(ws.results[command_id].last)
          #ws.close
        end
      end
    end
  end
end
