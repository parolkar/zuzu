# frozen_string_literal: true

module Zuzu
  # Manages the llamafile subprocess lifecycle.
  class LlamafileManager
    STARTUP_TIMEOUT  = 60   # seconds — models can take a while
    SHUTDOWN_TIMEOUT = 5

    attr_reader :pid

    def initialize(path: Zuzu.config.llamafile_path, port: Zuzu.config.port)
      @path   = path
      @port   = port
      @pid    = nil
      @client = LlmClient.new(port: @port)
    end

    def start!
      raise "llamafile already running (pid=#{@pid})" if running?
      raise "llamafile not found: #{@path}" unless File.exist?(@path.to_s)

      log_file = File.expand_path('llama.log', File.dirname(@path))
      @pid = Process.spawn(
        @path, '--server', '--port', @port.to_s, '--nobrowser',
        out: log_file, err: log_file
      )
      Process.detach(@pid)
      wait_for_ready
      @pid
    end

    def stop!
      return unless @pid
      Process.kill('TERM', @pid) rescue nil
      deadline = Time.now + SHUTDOWN_TIMEOUT
      while Time.now < deadline
        return (@pid = nil) unless alive?(@pid)
        sleep 0.25
      end
      Process.kill('KILL', @pid) rescue nil
      @pid = nil
    end

    def running?
      @pid && alive?(@pid)
    end

    private

    def wait_for_ready
      deadline = Time.now + STARTUP_TIMEOUT
      until @client.alive?
        if Time.now > deadline
          stop!
          raise "llamafile failed to start within #{STARTUP_TIMEOUT}s"
        end
        sleep 1
      end
    end

    def alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH, Errno::EPERM, Errno::EINVAL
      false
    end
  end
end
