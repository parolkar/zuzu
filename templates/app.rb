# frozen_string_literal: true

require 'zuzu'

# ── Configure ────────────────────────────────────────────────────
# Paths are automatically expanded to absolute, so relative paths work fine.
Zuzu.configure do |c|
  c.app_name       = 'My Assistant'
  # When running from a packaged jar, __dir__ is a classloader URI —
  # resolve paths against the directory where the jar was launched instead.
  base = __dir__.to_s.start_with?('uri:classloader:') ? Dir.pwd : __dir__
  c.llamafile_path = File.join(base, 'models', 'your-model.llamafile')
  c.db_path        = File.join(base, '.zuzu', 'zuzu.db')
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
