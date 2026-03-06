# frozen_string_literal: true

require 'zuzu'

# ── Configure ────────────────────────────────────────────────────
# Paths are automatically expanded to absolute, so relative paths work fine.
Zuzu.configure do |c|
  c.app_name       = 'My Assistant'
  c.llamafile_path = File.join(__dir__, 'models', 'your-model.llamafile')
  c.db_path        = File.join(__dir__, '.zuzu', 'zuzu.db')
  c.port           = 8080
  # c.channels     = ['whatsapp']
end

# ── Custom Tools ─────────────────────────────────────────────────
Zuzu::ToolRegistry.register(
  'greet', 'Greet a user by name.',
  { type: 'object', properties: { name: { type: 'string' } }, required: ['name'] }
) { |args, _fs| "Hello, #{args['name']}!" }

# ── Launch ───────────────────────────────────────────────────────
Zuzu::App.launch!(use_llamafile: true)
