# frozen_string_literal: true

Zuzu::ToolRegistry.register(
  'read_file', 'Read the contents of a file from the sandbox filesystem.',
  { type: 'object', properties: { path: { type: 'string', description: 'Absolute path' } }, required: ['path'] }
) { |args, fs| fs.read_file(args['path']) || "File not found: #{args['path']}" }

Zuzu::ToolRegistry.register(
  'write_file', 'Write content to a file in the sandbox filesystem.',
  { type: 'object', properties: {
    path:    { type: 'string', description: 'Absolute path' },
    content: { type: 'string', description: 'Content to write' }
  }, required: %w[path content] }
) do |args, fs|
  fs.write_file(args['path'], args['content'])
  "Written #{args['content'].to_s.bytesize} bytes to #{args['path']}"
end

Zuzu::ToolRegistry.register(
  'list_directory', 'List entries in a directory.',
  { type: 'object', properties: { path: { type: 'string', description: 'Directory path (default "/")' } }, required: [] }
) do |args, fs|
  entries = fs.list_dir(args['path'] || '/')
  entries.empty? ? '(empty)' : entries.join("\n")
end
