# frozen_string_literal: true

require 'glimmer-dsl-swt'

module Zuzu
  class App
    include Glimmer::UI::Application

    USER_BG   = rgb(66, 133, 244)
    ASSIST_BG = rgb(225, 235, 255)

    attr_accessor :user_input

    before_body do
      @store    = Store.new
      @fs       = AgentFS.new(@store)
      @memory   = Memory.new(@store)
      @llm      = LlmClient.new
      @agent    = Agent.new(agent_fs: @fs, memory: @memory, llm: @llm)
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

        # ── Chat display ─────────────────────────────────────
        scrolled_composite(:v_scroll) {
          layout_data(:fill, :fill, true, true)

          @chat_display = text(:multi, :read_only, :wrap) {
            background :white
            font name: 'Monospace', height: 13
          }
        }

        # ── Input row ────────────────────────────────────────
        composite {
          layout_data(:fill, :fill, true, false)
          grid_layout 3, false

          @input_text = text(:border) {
            layout_data(:fill, :fill, true, false)
            text <=> [self, :user_input]
            on_key_pressed do |e|
              send_message if e.character == 13
            end
          }

          button {
            text 'Send'
            on_widget_selected { send_message }
          }

          button {
            text 'Admin Panel'
            on_widget_selected { open_admin_panel }
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
          response = @agent.process(input) do |tool_name, args, result|
            async_exec { add_bubble(:tool, "#{tool_name}(#{args.map { |k, v| "#{k}: #{v.to_s[0, 40]}" }.join(', ')}) → #{result.to_s[0, 80]}") }
          end
          async_exec { add_bubble(:assistant, response) }
        rescue => e
          $stderr.puts "[zuzu] Send error: #{e.message}"
          async_exec { add_bubble(:assistant, "Error: #{e.message}") }
        end
      end
    end

    def add_bubble(role, msg)
      prefix = case role
               when :user      then "You: "
               when :assistant then "Assistant: "
               when :tool      then "  [tool] "
               end
      current   = @chat_display.swt_widget.get_text
      separator = role == :tool ? "\n" : "\n\n"
      separator = '' if current.empty?
      @chat_display.swt_widget.set_text(current + separator + prefix + msg.to_s)
      @chat_display.swt_widget.set_top_index(@chat_display.swt_widget.get_line_count)
    end

    def open_admin_panel
      file_list_widget = nil

      admin = shell {
        text 'Admin Panel'
        minimum_size 380, 500
        grid_layout 1, false

        label {
          layout_data(:fill, :fill, true, false)
          text 'AgentFS — Virtual File Browser'
          font height: 12, style: :bold
        }

        file_list_widget = list(:single, :v_scroll, :border) {
          layout_data(:fill, :fill, true, true)
          font name: 'Monospace', height: 11
        }

        button {
          layout_data(:fill, :fill, true, false)
          text 'Create Test File'
          on_widget_selected {
            @fs.write_file('/test.txt', "Hello from AgentFS!\nCreated at: #{Time.now}")
            populate_file_list(file_list_widget)
          }
        }

        button {
          layout_data(:fill, :fill, true, false)
          text 'Clear Chat History'
          on_widget_selected {
            @memory.clear
            message_box {
              text 'Done'
              message 'Conversation history cleared.'
            }.open
          }
        }

        button {
          layout_data(:fill, :fill, true, false)
          text 'Refresh'
          on_widget_selected { populate_file_list(file_list_widget) }
        }
      }

      populate_file_list(file_list_widget)
      admin.open
    end

    def populate_file_list(file_list)
      entries = walk_fs('/')
      items = entries.empty? ? ['(empty)'] : entries
      file_list.swt_widget.set_items(items.to_java(:string))
    rescue => e
      file_list.swt_widget.set_items(["Error: #{e.message}"].to_java(:string))
    end

    def walk_fs(path, indent = 0)
      @fs.list_dir(path).flat_map do |name|
        child = path == '/' ? "/#{name}" : "#{path}/#{name}"
        stat  = @fs.stat(child)
        if stat && stat['type'] == 'dir'
          ["#{'  ' * indent}+ #{name}/"] + walk_fs(child, indent + 1)
        else
          ["#{'  ' * indent}  #{name}"]
        end
      end
    end
  end
end
