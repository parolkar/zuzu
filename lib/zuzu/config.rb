# frozen_string_literal: true

module Zuzu
  # Central configuration singleton.
  #
  #   Zuzu.configure do |c|
  #     c.app_name       = "My Agent"
  #     c.llamafile_path = "models/my.llamafile"
  #     c.port           = 8080
  #   end
  #
  class Config
    attr_accessor :port, :model, :channels, :log_level, :app_name,
                  :window_width, :window_height, :system_prompt_extras

    attr_reader :db_path, :llamafile_path

    def initialize
      @port           = 8080
      @model          = 'LLaMA_CPP'
      @db_path        = File.join('.zuzu', 'zuzu.db')
      @llamafile_path = nil
      @channels             = []
      @log_level            = :info
      @system_prompt_extras = nil
      @app_name       = 'Zuzu'
      @window_width   = 860
      @window_height  = 620
    end

    # Expand paths so relative paths resolve against the caller's directory,
    # not whatever the current working directory happens to be at runtime.
    def db_path=(path)
      @db_path = path ? File.expand_path(path) : path
    end

    def llamafile_path=(path)
      @llamafile_path = path ? File.expand_path(path) : path
    end
  end

  @config = Config.new

  def self.config
    yield @config if block_given?
    @config
  end

  class << self
    alias_method :configure, :config
  end
end
