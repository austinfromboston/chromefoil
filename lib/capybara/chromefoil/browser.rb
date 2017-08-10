require "capybara/chromefoil/command"
require 'json'
require 'time'

module Capybara::Chromefoil
  class Browser
    ERROR_MAPPINGS = {
      #'Chromefoil.JavascriptError' => JavascriptError,
      #'Chromefoil.FrameNotFound'   => FrameNotFound,
      #'Poltergeist.InvalidSelector' => InvalidSelector,
      #'Poltergeist.StatusFailError' => StatusFailError,
      #'Poltergeist.NoSuchWindowError' => NoSuchWindowError,
      #'Poltergeist.UnsupportedFeature' => UnsupportedFeature,
      #'Poltergeist.KeyError' => KeyError,
    }

    attr_reader :server, :client, :logger

    def initialize(server, client, logger = nil)
      @server = server
      @client = client
      @logger = logger
    end

    def restart
      server.restart
      client.restart

      self.debug = @debug if defined?(@debug)
      self.js_errors = @js_errors if defined?(@js_errors)
      self.extensions = @extensions if @extensions
    end

    def visit(url)
      command 'Network.enable'
      command 'Page.navigate', url: url
    end

    def current_url
      server.socket.current_url
    end

    def status_code
      server.socket.last_status_code
    end

    def body
      doc = command "DOM.getDocument"
      docNode = doc.fetch('root', {})
      htmlNode = docNode['children'].find do |n|
        n['nodeName'] == "HTML"
      end
      bodyNode = htmlNode['children'].find do |n|
        n['nodeName'] == 'BODY'
      end
      command("DOM.getOuterHTML", nodeId: bodyNode['nodeId']).fetch('outerHTML')
    end

    def source
      doc = command "DOM.getDocument"
      docNode = doc.fetch('root', {})
      command("DOM.getOuterHTML", nodeId: docNode['nodeId']).fetch('outerHTML')
    end

    def title
      server.socket.current_page_title
    end

    def parents(node_id)
      command "DOM.enable"
      doc = command "DOM.getFlattenedDocument", depth: -1
      nodes_by_id = doc['nodes'].reduce({}) { |memo, n| memo[n['nodeId']] = n; memo }
      target_node = nodes_by_id[node_id]
      parents = []
      while target_node && target_node.has_key?('parentId')
        parent_node = nodes_by_id[target_node['parentId']]
        parents << parent_node if parent_node
        target_node = parent_node
      end
      parents
    end

    def find(method, selector)
      if method == :xpath
        # this one only works with propriatary path, not xpath
        #result = command "DOM.pushNodeByPathToFrontend", path: selector

        # get the length of matching nodeset from the console then query for each one
        # this one should work but the nodeId always comes back as 0
        raise "who is even using xpath?"
        exp = "$x('#{selector}').length;"

        match_length = b.command "Runtime.evaluate", expression: exp, includeCommandLineAPI: true

        (0...match_length['result']['value']).map do |i|
          exp2 = "$x('#{selector}')[#{i}];"
          search = b.command "Runtime.evaluate", expression: exp2,  includeCommandLineAPI: true
          nodeResult = b.command "DOM.requestNode", objectId: search['result']['objectId']
          nodeResult['nodeId']
        end
      elsif method == :css
        doc = command "DOM.getDocument"
        docNode = doc.fetch('root', {})
        result = command "DOM.querySelectorAll", selector: selector, nodeId: docNode['nodeId']
        result['nodeIds']
      else
        raise "find method: #{method} not supported"
      end
    end

    def find_within(node_id, method, selector)
      if method == :xpath
        # probably a big box of fail
        baseNode = command "DOM.resolveNode", nodeId: node_id

        exp = <<-XPATH
          function(search_xpath)
            var x = document.evaluate(
             search_xpath,
             this,
             null,
             XPathResult.ANY_TYPE,
             null
            );
            var x2 = [];
            while(x2[x2.length] = x.iterateNext()) {};
            return x2;
          }
        XPATH

        foundNodes = command "Runtime.callFunctionOn", objectId: baseNode['result']['objectId'], functionDeclaration: exp, arguments: [selector]
        # some kind of transformation on foundNodes if this even worked
      elsif method == :css
        result = command "DOM.querySelectorAll", selector: selector, nodeId: node_id
        result['nodeIds']
      else
        raise "find_within method: #{method} not supported"
      end
    end

    def all_text(node_id)
      object_ref = command "DOM.resolveNode", nodeId: node_id
      script = "function() { return this.textContent; }"
      result = command 'Runtime.callFunctionOn', objectId: object_ref['object']['objectId'], functionDeclaration: script
      result['result']['value']
    end

    def visible_text(node_id)
      object_ref = command "DOM.resolveNode", nodeId: node_id
      script = "function() { return this.innerText; }"
      result = command 'Runtime.callFunctionOn', objectId: object_ref['object']['objectId'], functionDeclaration: script
    end

    def delete_text(node_id)
      object_ref = command "DOM.resolveNode", nodeId: node_id
      script = "function() { this.innerText = ''; }"
      command 'Runtime.callFunctionOn', objectId: object_ref['object']['objectId'], functionDeclaration: script
    end

    def property(node_id, name)
      container_object = b.command "DOM.resolveNode", nodeId: node_id
      script = 'function(propertyName) { return this[propertyName]; }'
      result = command "Runtime.callFunctionOn", objectId: container_object['object']['objectId'], functionDeclaration: script
      result['value']
    end

    def attributes(node_id)
      result = command "DOM.getAttributes", nodeId: node_id
      Hash[*result['attributes']]
    end

    def attribute(node_id, name)
      attributes(node_id)[name]
    end

    def value(node_id)
      property(node_id, 'value')
    end

    def set(node_id, value)
      container_object = b.command "DOM.resolveNode", nodeId: node_id
      script = 'function(value) { this.value = value; }'
      command "Runtime.callFunctionOn", objectId: container_object['object']['objectId'], functionDeclaration: script, arguments: [value]
    end

    def select_file(node_id, value)
      command "DOM.setFileInputFiles", nodeId: node_id, files: [value]
    end

    def tag_name(node_id)
      result = command "DOM.resolveNode", nodeId: node_id
      result['object']['description']
    end

    def visible?(page_id, id)
      container_object = b.command "DOM.resolveNode", nodeId: node_id
      script = "function() { return !!( this.offsetWidth || this.offsetHeight || this.getClientRects().length ); }"
      result = command "Runtime.callFunctionOn", objectId: container_object['object']['objectId'], functionDeclaration: script
      result['result']['value']
    end

    def disabled?(node_id)
      attribute(node_id, "disabled")
    end

    def click_coordinates(x, y)
      command "Input.dispatchMouseEvent", type: "mousePressed", x: x, y: y
      command "Input.dispatchMouseEvent", type: "mouseReleased", x: x, y: y
    end

    def evaluate(script, *args)
      # not clear what the args are for...
      command "Runtime.evaluate", expression: script
    end

    def execute(script, *args)
      # not clear what the args are for...
      command "Runtime.evaluate", expression: script
    end

    def within_frame(handle, &block)
      if handle.is_a?(Capybara::Node::Base)
        command 'push_frame', [handle.native.page_id, handle.native.id]
      else
        command 'push_frame', handle
      end

      yield
    ensure
      command 'pop_frame'
    end

    def switch_to_frame(handle, &block)
      case handle
      when Capybara::Node::Base
        command 'push_frame', [handle.native.page_id, handle.native.id]
      when :parent
        command 'pop_frame'
      when :top
        command 'pop_frame', true
      end
    end

    def window_handle
      command 'window_handle'
    end

    def window_handles
      command 'window_handles'
    end

    def switch_to_window(handle)
      command 'switch_to_window', handle
    end

    def open_new_window
      command 'open_new_window'
    end

    def close_window(handle)
      command 'close_window', handle
    end

    def find_window_handle(locator)
      return locator if window_handles.include? locator

      handle = command 'window_handle', locator
      raise NoSuchWindowError unless handle
      return handle
    end

    def within_window(locator, &block)
      original = window_handle
      handle = find_window_handle(locator)
      switch_to_window(handle)
      yield
    ensure
      switch_to_window(original)
    end

    def click(node_id)
      command "DOM.getBoxModel", nodeId: node_id
      box = b.command "DOM.getBoxModel", nodeId: my_link
      xy = [(box['model']['content'][0] + box['model']['width'] / 2), (box['model']['content'][1] + box['model']['height'] / 2)]

      b.click_coordinates *xy
    end

    def right_click(page_id, id)
      command 'right_click', page_id, id
    end

    def double_click(page_id, id)
      command 'double_click', page_id, id
    end

    def hover(page_id, id)
      command 'hover', page_id, id
    end

    def drag(page_id, id, other_id)
      command 'drag', page_id, id, other_id
    end

    def drag_by(page_id, id, x, y)
      command 'drag_by', page_id, id, x, y
    end

    def select(page_id, id, value)
      command 'select', page_id, id, value
    end

    def trigger(page_id, id, event)
      command 'trigger', page_id, id, event.to_s
    end

    def reset
      command 'reset'
    end

    def scroll_to(left, top)
      command 'scroll_to', left, top
    end

    def render(path, options = {})
      check_render_options!(options)
      options[:full] = !!options[:full]
      command 'render', path.to_s, options
    end

    def render_base64(format, options = {})
      check_render_options!(options)
      options[:full] = !!options[:full]
      command 'render_base64', format.to_s, options
    end

    def set_zoom_factor(zoom_factor)
      command 'set_zoom_factor', zoom_factor
    end

    def set_paper_size(size)
      command 'set_paper_size', size
    end

    def resize(width, height)
      command 'resize', width, height
    end

    def send_keys(page_id, id, keys)
      command 'send_keys', page_id, id, normalize_keys(keys)
    end

    def path(page_id, id)
      command 'path', page_id, id
    end

    def network_traffic(type = nil)
      command('network_traffic', type).map do |event|
        NetworkTraffic::Request.new(
          event['request'],
          event['responseParts'].map { |response| NetworkTraffic::Response.new(response) },
          event['error'] ? NetworkTraffic::Error.new(event['error']) : nil
        )
      end
    end

    def clear_network_traffic
      command('clear_network_traffic')
    end

    def set_proxy(ip, port, type, user, password)
      args = [ip, port, type]
      args << user if user
      args << password if password
      command('set_proxy', *args)
    end

    def equals(page_id, id, other_id)
      command('equals', page_id, id, other_id)
    end

    def get_headers
      command 'get_headers'
    end

    def set_headers(headers)
      command 'set_headers', headers
    end

    def add_headers(headers)
      command 'add_headers', headers
    end

    def add_header(header, options={})
      command 'add_header', header, options
    end

    def response_headers
      command 'response_headers'
    end

    def cookies
      Hash[command('cookies').map { |cookie| [cookie['name'], Cookie.new(cookie)] }]
    end

    def set_cookie(cookie)
      if cookie[:expires]
        cookie[:expires] = cookie[:expires].to_i * 1000
      end

      command 'set_cookie', cookie
    end

    def remove_cookie(name)
      command 'remove_cookie', name
    end

    def clear_cookies
      command 'clear_cookies'
    end

    def cookies_enabled=(flag)
      command 'cookies_enabled', !!flag
    end

    def set_http_auth(user, password)
      command 'set_http_auth', user, password
    end

    def js_errors=(val)
      @js_errors = val
      command 'set_js_errors', !!val
    end

    def extensions=(names)
      @extensions = names
      Array(names).each do |name|
        command 'add_extension', name
      end
    end

    def url_whitelist=(whitelist)
      command 'set_url_whitelist', *whitelist
    end

    def url_blacklist=(blacklist)
      command 'set_url_blacklist', *blacklist
    end

    def debug=(val)
      @debug = val
      command 'set_debug', !!val
    end

    def clear_memory_cache
      command 'clear_memory_cache'
    end

    def command(name, params={})
      cmd = Command.new(name, params)
      log cmd.message

      response = server.send(cmd)
      log response

      json = JSON.load(response)

      if json['error']
        klass = ERROR_MAPPINGS[json['error']['name']] || BrowserError
        raise klass.new(json['error'])
      else
        json['result']
      end
    rescue DeadClient
      restart
      raise
    end

    def go_back
      command 'go_back'
    end

    def go_forward
      command 'go_forward'
    end

    def refresh
      command 'refresh'
    end

    def accept_confirm
      command 'set_confirm_process', true
    end

    def dismiss_confirm
      command 'set_confirm_process', false
    end

    #
    # press "OK" with text (response) or default value
    #
    def accept_prompt(response)
      command 'set_prompt_response', response || false
    end

    #
    # press "Cancel"
    #
    def dismiss_prompt
      command 'set_prompt_response', nil
    end

    def modal_message
      command 'modal_message'
    end

    private

    def log(message)
      logger.puts message if logger
    end

    def check_render_options!(options)
      if !!options[:full] && options.has_key?(:selector)
        warn "Ignoring :selector in #render since :full => true was given at #{caller.first}"
        options.delete(:selector)
      end
    end

    KEY_ALIASES = {
      command:   :Meta,
      equals:    :Equal,
      Control:   :Ctrl,
      control:   :Ctrl,
      multiply:  'numpad*',
      add:       'numpad+',
      divide:    'numpad/',
      subtract:  'numpad-',
      decimal:   'numpad.'
    }

    def normalize_keys(keys)
      keys.map do |key_desc|
        case key_desc
        when Array
          # [:Shift, "s"] => { modifier: "shift", keys: "S" }
          # [:Shift, "string"] => { modifier: "shift", keys: "STRING" }
          # [:Ctrl, :Left] => { modifier: "ctrl", key: 'Left' }
          # [:Ctrl, :Shift, :Left] => { modifier: "ctrl,shift", key: 'Left' }
          # [:Ctrl, :Left, :Left] => { modifier: "ctrl", key: [:Left, :Left] }
          _keys = key_desc.chunk {|k| k.is_a?(Symbol) && %w(shift ctrl control alt meta command).include?(k.to_s.downcase) }
          modifiers = if _keys.peek[0]
            _keys.next[1].map do |k|
              k = k.to_s.downcase
              k = 'ctrl' if k == 'control'
              k = 'meta' if k == 'command'
              k
            end.join(',')
          else
            ''
          end
          letters = normalize_keys(_keys.next[1].map {|k| k.is_a?(String) ? k.upcase : k })
          { modifier: modifiers, keys: letters }
        when Symbol
          # Return a known sequence for PhantomJS
          key = KEY_ALIASES.fetch(key_desc, key_desc)
          if match = key.to_s.match(/numpad(.)/)
            res = { keys: match[1], modifier: 'keypad' }
          elsif key !~ /^[A-Z]/
            key = key.to_s.split('_').map{ |e| e.capitalize }.join
          end
          res || { key: key }
        when String
          key_desc # Plain string, nothing to do
        end
      end
    end
  end
end
