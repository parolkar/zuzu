# frozen_string_literal: true

require 'glimmer-dsl-swt'

module Zuzu
  class App
    include Glimmer::UI::Application

    USER_BG   = rgb(66, 133, 244)
    ASSIST_BG = rgb(225, 235, 255)

    attr_accessor :user_input

    before_body do
      @store  = Store.new
      @fs     = AgentFS.new(@store)
      @memory = Memory.new(@store)
      @llm    = LlmClient.new
      @agent  = Agent.new(agent_fs: @fs, memory: @memory, llm: @llm)
      @user_input = ''

      @channels = [Channels::InApp.new(@agent)]
      if Zuzu.config.channels.include?('whatsapp')
        @channels << Channels::WhatsApp.new(@agent)
      end
      @channels.each(&:start)
    end

    after_body do
      body_root.on_widget_disposed do
        @channels.each(&:stop)
        @store.close
      end
    end

    body {
      shell {
        grid_layout 1, false
        text Zuzu.config.app_name
        size Zuzu.config.window_width, Zuzu.config.window_height

        # ── Chat messages area ────────────────────────────────
        @chat_scroll = scrolled_composite(:v_scroll) {
          layout_data(:fill, :fill, true, true)

          @chat_panel = composite {
            row_layout(:vertical) {
              fill          true
              margin_width  10
              margin_height 10
              spacing       6
            }
            background :white
          }
        }

        # ── Input row ─────────────────────────────────────────
        composite {
          layout_data(:fill, :fill, true, false)
          grid_layout 2, false

          @input_text = text(:border) {
            layout_data(:fill, :fill, true, true)
            text <=> [self, :user_input]
            on_key_pressed do |e|
              send_message if e.character == 13
            end
          }

          button {
            text 'Send'
            on_widget_selected { send_message }
          }
        }
      }
    }

    def self.launch!(use_llamafile: false)
      if use_llamafile
        @llamafile = LlamafileManager.new
        @llamafile.start!
      end
      launch
    ensure
      @llamafile&.stop!
    end

    private

    def send_message
      input = user_input.to_s.strip
      return if input.empty?

      self.user_input = ''
      add_bubble(:user, input)

      Thread.new do
        begin
          response = @agent.process(input)
          async_exec { add_bubble(:assistant, response) }
        rescue => e
          $stderr.puts "[zuzu] Send error: #{e.message}"
          async_exec { add_bubble(:assistant, "Error: #{e.message}") }
        end
      end
    end

    def add_bubble(role, msg)
      bg = role == :user ? USER_BG : ASSIST_BG
      fg = role == :user ? :white  : :black

      @chat_panel.content {
        label(:wrap) {
          text msg.to_s
          background bg
          foreground fg
        }
      }

      @chat_panel.swt_widget.layout(true, true)
      body_root.layout(true, true)
      @chat_scroll.set_origin(0, @chat_panel.swt_widget.size.y)
    end
  end
end
