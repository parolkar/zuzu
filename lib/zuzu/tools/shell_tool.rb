# frozen_string_literal: true

Zuzu::ToolRegistry.register(
  'run_command', 'Run a safe, read-only shell command and return stdout.',
  { type: 'object', properties: { command: { type: 'string', description: 'Shell command' } }, required: ['command'] }
) do |args, _fs|
  cmd   = args['command'].to_s.strip
  allow = %w[ls cat echo date whoami pwd uname hostname df free]
  base  = cmd.split(/\s+/).first
  unless allow.include?(base)
    next "Error: '#{base}' not in allowed list: #{allow.join(', ')}"
  end
  IO.popen(cmd, err: [:child, :out]) { |io| io.read }.to_s.slice(0, 4096)
end
