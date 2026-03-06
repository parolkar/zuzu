---
name: add-tool
description: Add a new tool that the Zuzu agent can call during conversations. Guides through naming, arguments, implementation, and registers it correctly in app.rb. Use when the developer wants the AI assistant to gain a new capability (e.g. check weather, query a database, read a file, call an API).
---

# Add a Zuzu Tool

A tool is a Ruby block the agent calls using `<zuzu_tool_call>` tags. Once registered, it is **automatically listed in the agent's system prompt** — no manual prompt editing needed.

## Step 1 — Understand what the tool should do

AskUserQuestion: "What should this tool do? Describe it in one sentence — this description will be shown to the AI agent."

AskUserQuestion: "What arguments does it need? For each: name, type (string/number/boolean), and what it represents. Or 'none' if no arguments."

AskUserQuestion: "Does it need to read/write files (use AgentFS), call an external API, query a database, or just compute something locally?"

## Step 2 — Choose a tool name

- Must be snake_case, descriptive, unambiguous
- Examples: `get_weather`, `search_notes`, `send_email`, `calculate_tax`, `lookup_stock_price`
- Check `app.rb` for existing tool names — avoid duplicates
- AskUserQuestion: "I'll name this tool `<suggested_name>`. Does that work, or would you prefer a different name?"

## Step 3 — Implement the tool

Read `app.rb` to find the insertion point — tools go **between the `Zuzu.configure` block and `Zuzu::App.launch!`**.

### Pattern A — No arguments, no AgentFS

```ruby
Zuzu::ToolRegistry.register(
  'tool_name',
  'One-sentence description shown to the agent.',
  { type: 'object', properties: {}, required: [] }
) { |_args, _fs| "result as a string" }
```

### Pattern B — With arguments

```ruby
Zuzu::ToolRegistry.register(
  'tool_name',
  'Description shown to the agent.',
  {
    type: 'object',
    properties: {
      param_one: { type: 'string', description: 'what it is' },
      param_two: { type: 'integer', description: 'what it is' }
    },
    required: ['param_one']   # list only truly required params
  }
) do |args, _fs|
  # args keys are STRINGS: args['param_one'] not args[:param_one]
  value = args['param_one'].to_s
  "result: #{value}"
end
```

### Pattern C — Using AgentFS (sandboxed file/KV access)

```ruby
Zuzu::ToolRegistry.register(
  'save_note',
  'Save a note to the virtual filesystem.',
  {
    type: 'object',
    properties: {
      title:   { type: 'string', description: 'Note title' },
      content: { type: 'string', description: 'Note content' }
    },
    required: %w[title content]
  }
) do |args, fs|
  # fs is Zuzu::AgentFS — sandboxed, NOT the host filesystem
  path = "/notes/#{args['title'].downcase.gsub(/\s+/, '_')}.txt"
  fs.write_file(path, args['content'])
  "Saved to #{path}"
end
```

### Pattern D — Calling an external HTTP API

```ruby
require 'net/http'
require 'json'

Zuzu::ToolRegistry.register(
  'get_weather',
  'Get current weather for a city using wttr.in.',
  {
    type: 'object',
    properties: {
      city: { type: 'string', description: 'City name' }
    },
    required: ['city']
  }
) do |args, _fs|
  uri = URI("https://wttr.in/#{URI.encode_uri_component(args['city'])}?format=3")
  Net::HTTP.get(uri).strip
rescue StandardError => e
  "Error fetching weather: #{e.message}"
end
```

## Step 4 — Enforce these rules before writing

Before inserting code, verify:

- [ ] Tool is placed **before** `Zuzu::App.launch!`
- [ ] Block signature uses `|args, fs|` or `|args, _fs|` (never zero args)
- [ ] `args` keys use **string** form: `args['name']` not `args[:name]`
- [ ] Return value is a **String** (or will be `.to_s`'d automatically)
- [ ] No `File.read` / `File.write` / `Dir` calls — use `fs` for file access
- [ ] External HTTP calls have a rescue block returning an error string
- [ ] Description is one clear sentence (the agent sees this verbatim)

Write the tool to `app.rb` now.

## Step 5 — Verify it loads

```bash
bundle exec ruby -e "
require 'zuzu'
load 'app.rb' rescue nil
tool = Zuzu::ToolRegistry.find('<tool_name>')
if tool
  puts 'Tool registered: ' + tool.name
  puts 'Description: ' + tool.description
else
  puts 'ERROR: tool not found'
end
" 2>&1
```

- If "tool not found": check for syntax errors, verify placement before `launch!`, retry.
- If syntax error printed: fix it, retry.

## Step 6 — Test in console (if possible without side effects)

```bash
bundle exec zuzu console
```

Then in the console:
```ruby
store = Zuzu::Store.new
fs    = Zuzu::AgentFS.new(store)
tool  = Zuzu::ToolRegistry.find('<tool_name>')
puts tool.block.call({'param' => 'test_value'}, fs)
```

- If it returns a sensible result: done.
- If error: fix and re-verify.

## Step 7 — Tell the user

Show the registered tool code and confirm:
> ✅ Tool `<name>` registered. The agent will now automatically list it in its system prompt and call it when relevant. Restart the app (`bundle exec zuzu start`) to pick up the change.

If the tool calls an external service that needs configuration (API key, URL, etc.):
> ⚠️ Remember to set `ENV['YOUR_API_KEY']` or add the value to your configuration before running.
