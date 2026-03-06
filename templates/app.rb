# frozen_string_literal: true

require 'zuzu'

# ── 1. Configure ─────────────────────────────────────────────────────────────
Zuzu.configure do |c|
  c.app_name      = 'My Assistant'     # Window title
  c.window_width  = 860
  c.window_height = 620
  c.port          = 8080               # llamafile API port

  # Works both when run directly and when packaged as a .jar
  base = __dir__.to_s.start_with?('uri:classloader:') ? Dir.pwd : __dir__
  c.llamafile_path = File.join(base, 'models', 'your-model.llamafile')
  c.db_path        = File.join(base, '.zuzu', 'zuzu.db')

  # ── Extra system prompt instructions (optional) ─────────────────────────
  # Append domain-specific behaviour, persona, or constraints to the agent's
  # system prompt. The built-in tool list is always included automatically.
  c.system_prompt_extras = <<~EXTRA
    You are a personal assistant for a software developer named Alex.
    Always prefer concise, technical answers.
    When writing code, use Ruby unless the user asks for another language.
  EXTRA
end

# ── 2. Custom tools ──────────────────────────────────────────────────────────
# Register tools the agent can call during conversations.
# The agent discovers them automatically — no prompt editing needed.
#
# Block signature: |args_hash, agent_fs|
#   args_hash — the JSON args the model passed (string keys)
#   agent_fs  — Zuzu::AgentFS instance for sandboxed file/KV access

Zuzu::ToolRegistry.register(
  'current_time',
  'Get the current local date and time.',
  { type: 'object', properties: {}, required: [] }
) { |_args, _fs| Time.now.strftime('%Y-%m-%d %H:%M:%S %Z') }

Zuzu::ToolRegistry.register(
  'greet',
  'Greet a user by name.',
  { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] }
) { |args, _fs| "Hello, #{args['name']}! Welcome." }

# ── 3. UI customisation ──────────────────────────────────────────────────────
# Basic customisation (app name, window size) is handled via Zuzu.configure above.
#
# For deeper UI changes subclass Zuzu::App and call launch! on your subclass:
#
#   class MyApp < Zuzu::App
#     # Override private helpers, e.g. change the Admin Panel contents:
#     def open_admin_panel
#       super   # keep default panel, or replace entirely
#     end
#   end
#   MyApp.launch!(use_llamafile: true)
#
# See lib/zuzu/app.rb in the zuzu gem source for the full shell/body definition.

# ── Launch ───────────────────────────────────────────────────────────────────
Zuzu::App.launch!(use_llamafile: true)
