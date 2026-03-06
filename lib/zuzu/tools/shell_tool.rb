# frozen_string_literal: true

Zuzu::ToolRegistry.register(
  'run_command', 'Run a sandboxed command against AgentFS (NOT the host filesystem).',
  { type: 'object', properties: { command: { type: 'string', description: 'Sandboxed command' } }, required: ['command'] }
) do |args, fs|
  cmd   = args['command'].to_s.strip
  parts = cmd.split(/\s+/)
  base  = parts[0]

  case base
  when 'ls'
    path = parts[1] || '/'
    stat = fs.stat(path)
    if stat && stat['type'] == 'file'
      "#{path} (file, #{stat['size']} bytes)"
    else
      entries = fs.list_dir(path)
      entries.empty? ? '(empty directory)' : entries.join("\n")
    end
  when 'cat'
    path = parts[1]
    path ? (fs.read_file(path) || "File not found in AgentFS: #{path}") : 'Usage: cat <path>'
  when 'pwd'
    '/'
  when 'echo'
    parts[1..].join(' ')
  else
    "Error: '#{base}' is not available in the AgentFS sandbox. Supported: ls, cat, pwd, echo."
  end
end
