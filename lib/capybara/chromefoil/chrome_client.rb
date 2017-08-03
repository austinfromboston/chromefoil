require 'timeout'
require 'securerandom'
require 'capybara/chromefoil/utility'

module Capybara::Chromefoil
  class ChromeClient

    KILL_TIMEOUT = 2 # seconds

    def self.start(*args)
      client = new(*args)
      client.start
      client
    end

    def self.process_killer(pid)
      proc do
        begin
          if Capybara::Chromefoil.windows?
            Process.kill('KILL', pid)
          else
            Process.kill('TERM', pid)
            start = Time.now
            while Process.wait(pid, Process::WNOHANG).nil?
              sleep 0.05
              if (Time.now - start) > KILL_TIMEOUT
                Process.kill('KILL', pid)
                Process.wait(pid)
                break
              end
            end
          end
        rescue Errno::ESRCH, Errno::ECHILD
          # process already dead
        end

      end
    end

    attr_reader :pid, :server, :path, :window_size, :chrome_options, :user_data_dir

    def initialize(server, options = {})
      @server = server
      @path = options[:path] || "/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome"
      @window_size = options[:window_size] || "1440,900"
      @chrome_options = options[:chrome_options] || []
      @chrome_logger = options[:chrome_logger] || $stdout
      @user_data_dir = options[:user_data_dir] || "/tmp/chromefoil_session_#{SecureRandom.hex(8)}"
    end

    def start
      @read_io, @write_io = IO.pipe
      @out_thread = Thread.new {
        while !@read_io.eof? && data = @read_io.readpartial(1024)
          @chrome_logger.write(data)
        end
      }

      process_options = {}
      process_options[:pgroup] = true unless Capybara::Chromefoil.windows?
      process_options[:out] = @write_io if Capybara::Chromefoil.mri?

      redirect_stdout do
        start_command = command.join(" ")
        p "Start command: #{start_command}"
        @pid = Process.spawn(*command.map(&:to_s), process_options)
        ObjectSpace.define_finalizer(self, self.class.process_killer(@pid))
      end
    end

    def stop
      if pid
        kill_chrome
        @out_thread.kill
        close_io
        ObjectSpace.undefine_finalizer(self)
      end
    end

    def restart
      stop
      start
    end

    def command
      [path,
       "--remote-debugging-port=#{server.port}",
       "--no-first-run",
       "--disable-sync",
       "--user-data-dir=#{user_data_dir}",
       "--window-size=#{window_size}"
      ] + Array(chrome_options)
    end

    private

    # full credit: teampoltergeist

    # This abomination is because JRuby doesn't support the :out option of
    # Process.spawn. To be honest it works pretty bad with pipes too, because
    # we ought close writing end in parent process immediately but JRuby will
    # lose all the output from child. Process.popen can be used here and seems
    # it works with JRuby but I've experienced strange mistakes on Rubinius.
    def redirect_stdout
      if Capybara::Chromefoil.mri?
        yield
      else
        begin
          prev = STDOUT.dup
          $stdout = @write_io
          STDOUT.reopen(@write_io)
          yield
        ensure
          STDOUT.reopen(prev)
          $stdout = STDOUT
          prev.close
        end
      end
    end

    def kill_chrome
      self.class.process_killer(pid).call
      @pid = nil
    end

    # We grab all the output from the client process in another thread
    # and when chrome crashes we try to restart it. In order to do it we stop
    # server and client and on JRuby see this error `IOError: Stream closed`.
    # It happens because JRuby tries to close pipe and it is blocked on `eof?`
    # or `readpartial` call. The error is raised in the related thread and it's
    # not actually main thread but the thread that listens to the output. That's
    # why if you put some debug code after `rescue IOError` it won't be shown.
    # In fact the main thread will continue working after the error even if we
    # don't use `rescue`. The first attempt to fix it was a try not to block on
    # IO, but looks like similar issue appers after JRuby upgrade. Perhaps the
    # only way to fix it is catching the exception what this method overall does.
    def close_io
      [@write_io, @read_io].each do |io|
        begin
          io.close unless io.closed?
        rescue IOError
          raise unless RUBY_ENGINE == 'jruby'
        end
      end
    end

  end
end
