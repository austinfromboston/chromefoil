require "net/http"
require "uri"
require 'json'
require 'websocket-client-simple'


module Chromefoil
  class Client
    attr_reader :host, :port, :uri
    attr_accessor :tabs, :ws

    def initialize(host: "localhost", port: 9222)
      @host = host
      @port = port
      @domains = {}
      @message_id = 0
    end

    def starting_point_url
      "http://#{host}:#{port}/json"
    end

    def remote_debugger_url(tab_index=0)
      uri = URI.parse(starting_point_url)
      response = Net::HTTP.get_response(uri)
      self.tabs = JSON.parse(response.body)
      tabs[tab_index]['webSocketDebuggerUrl']
    end

    def connect(tab_index=0)
      self.ws = WebSocket::Client::Simple.connect remote_debugger_url(tab_index)

      ws.on :message do |msg|
        puts msg.data
      end

      ws.on :open do
        p 'hello!!! socket open'
      end

      ws.on :close do |e|
        p e
        exit 1
      end

      ws.on :error do |e|
        p e
      end

      yield ws if block_given?
    end

    def send_message(message)
      instance_eval("self.#{message}", __FILE__, __LINE__) if message.size > 0
    end

    def next_message_id
      @message_id += 1
    end

    def method_missing(method_name)
      eigenclass = class << self; self; end
      eigenclass.class_eval do
        define_method method_name do
          @domains[method_name] ||= ApiDomain.new(method_name, self)
        end
      end
      send(method_name)

    end

  end

  class ApiDomain
    def initialize(name, client)
      @name = name
      @client = client
    end
    def method_missing(method_name, *args)
      domain_method_name = "#{@name}.#{method_name}"
      final_message = JSON.dump({id: @client.next_message_id, method: domain_method_name, params: args[0]}) 
      p "cc sending #{final_message}"
      @client.ws.send final_message
    end
  end
end
