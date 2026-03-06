# CLAUDE.md — Zuzu App Development Guide

This is a **Zuzu** application — a JRuby desktop AI assistant built on
Glimmer DSL for SWT, SQLite (via JDBC), and a local llamafile LLM.

## Runtime

- **JRuby 10.0.3.0** — required (NOT MRI Ruby)
- **Java 21+** — required for SWT and JDBC
- Install: `rbenv install jruby-10.0.3.0 && rbenv local jruby-10.0.3.0`
- Verify: `ruby -v` → should show `jruby 10.0.3.0`

## Common commands

```bash
bundle exec zuzu start      # launch the desktop app
bundle exec zuzu console    # IRB session with Zuzu loaded
bundle exec zuzu package    # package as standalone .jar
bundle install              # install / sync gems
```

## Key files

| File | Role |
|------|------|
| `app.rb` | **Your main file** — configure, register tools, launch |
| `models/` | Place llamafile model binaries here (not bundled in .jar) |
| `.zuzu/zuzu.db` | SQLite database — AgentFS + conversation memory |
| `Gemfile` | Gem dependencies |
| `warble.rb` | Warbler config for `zuzu package` |

## app.rb structure

```ruby
Zuzu.configure do |c|
  c.app_name             = 'My App'
  c.llamafile_path       = File.join(base, 'models', 'model.llamafile')
  c.db_path              = File.join(base, '.zuzu', 'zuzu.db')
  c.port                 = 8080
  c.system_prompt_extras = "Extra instructions for the agent..."
end

Zuzu::ToolRegistry.register('tool_name', 'description', schema) { |args, fs| result }

Zuzu::App.launch!(use_llamafile: true)
```

## Adding a tool (most common task)

```ruby
Zuzu::ToolRegistry.register(
  'tool_name',                          # called by agent in <zuzu_tool_call> tags
  'One-sentence description.',          # shown to the agent in system prompt
  {
    type: 'object',
    properties: {
      param: { type: 'string', description: 'what it is' }
    },
    required: ['param']
  }
) do |args, fs|
  # args — Hash with string keys  e.g. args['param']
  # fs   — Zuzu::AgentFS instance (sandboxed, NOT host filesystem)
  "return value as string"
end
```

The tool is **automatically added to the agent's system prompt** — no manual
prompt editing needed.

## Customising the system prompt

```ruby
c.system_prompt_extras = <<~EXTRA
  You are a personal assistant for a Ruby developer.
  Always prefer concise, technical answers.
EXTRA
```

## AgentFS quick reference

The agent operates in a sandboxed SQLite-backed virtual filesystem.
It is completely isolated from the host machine's files.

```ruby
fs.write_file('/notes/todo.txt', 'content')   # create/overwrite
fs.read_file('/notes/todo.txt')               # → String or nil
fs.list_dir('/notes')                         # → ['todo.txt']
fs.mkdir('/new/dir')                          # → true
fs.delete('/notes/todo.txt')                  # → true
fs.exists?('/notes/todo.txt')                 # → true/false
fs.stat('/notes/todo.txt')                    # → {'type'=>'file','size'=>7,...}
fs.kv_set('key', 'value')                     # persistent key-value store
fs.kv_get('key')                              # → 'value' or nil
```

## Glimmer DSL — what works on this platform

Always run UI updates on the SWT thread:

```ruby
async_exec { @chat_display.swt_widget.set_text(...) }   # safe from any thread
Thread.new { response = @agent.process(msg); async_exec { add_bubble(...) } }
```

For UI extension details see AGENTS.md.

## What NOT to do

- Never call `ruby app.rb` directly — always use `bundle exec zuzu start`
- Never use `File.read` / `File.write` for agent data — use `AgentFS`
- Never modify `.zuzu/zuzu.db` manually while the app is running
- Never call SWT widget methods from a background thread without `async_exec`
- Never `require 'glimmer-dsl-swt'` in `app.rb` — it's already loaded by Zuzu
