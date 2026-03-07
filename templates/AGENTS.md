# AGENTS.md — Zuzu App Development Reference

Comprehensive guide for AI coding assistants (Claude Code, OpenCode, etc.)
extending a Zuzu desktop application.

---

## What is Zuzu?

Zuzu is a JRuby desktop framework for local-first AI assistants.
An app consists of:

1. **`app.rb`** — configure + register tools + launch (the only file you normally edit)
2. **Glimmer DSL for SWT GUI** — native desktop window (chat area + input row)
3. **Agent loop** — prompt-based ReAct loop using `<zuzu_tool_call>` XML tags
4. **AgentFS** — SQLite-backed virtual filesystem sandboxed from the host OS
5. **llamafile** — local LLM subprocess serving an OpenAI-compatible HTTP API

---

## Runtime requirements

| Component | Version |
|-----------|---------|
| JRuby | 10.0.3.0 |
| Java | 21+ |
| Bundler | any recent |

```bash
rbenv install jruby-10.0.3.0
rbenv local jruby-10.0.3.0
bundle install
bundle exec zuzu start
```

---

## Architecture overview

```
app.rb
  └── Zuzu.configure(...)           # app_name, model path, port, extras
  └── Zuzu::ToolRegistry.register   # custom tools
  └── Zuzu::App.launch!             # starts llamafile + opens SWT window

Zuzu::App (Glimmer::UI::Application)
  └── before_body: creates Store, AgentFS, Memory, LlmClient, Agent, Channels
  └── body: SWT shell (chat display + input row + Admin Panel button)
  └── send_message → Thread.new → Agent#process → async_exec (UI update)

Zuzu::Agent#process(user_message)
  └── builds system prompt (BASE_PROMPT + registered tools + config.system_prompt_extras)
  └── LlmClient#chat → parses <zuzu_tool_call> tags → ToolRegistry#execute
  └── loops up to 10 times until no tool calls remain
  └── stores final answer in Memory

Zuzu::ToolRegistry
  └── global registry of Tool structs (name, description, schema, block)
  └── tools are auto-listed in system prompt — no manual prompt editing

Zuzu::AgentFS
  └── SQLite virtual filesystem (fs_inodes + fs_dentries + kv_store + tool_calls)
  └── completely isolated from host filesystem

Zuzu::LlmClient
  └── HTTP POST to http://127.0.0.1:<port>/v1/chat/completions
  └── temperature 0.1 (deterministic, important for tool use)
  └── strips llamafile EOS tokens from response
```

---

## Adding a custom tool

This is the most common extension point. Tools are Ruby blocks registered
before `Zuzu::App.launch!` in `app.rb`.

### Minimal example

```ruby
Zuzu::ToolRegistry.register(
  'current_time',
  'Get the current local date and time.',
  { type: 'object', properties: {}, required: [] }
) { |_args, _fs| Time.now.strftime('%Y-%m-%d %H:%M:%S %Z') }
```

### With arguments

```ruby
Zuzu::ToolRegistry.register(
  'calculate',
  'Evaluate a simple Ruby arithmetic expression safely.',
  {
    type: 'object',
    properties: {
      expression: { type: 'string', description: 'e.g. "2 + 2 * 10"' }
    },
    required: ['expression']
  }
) do |args, _fs|
  allowed = args['expression'].to_s.gsub(/[^0-9+\-*\/\(\)\.\s]/, '')
  eval(allowed).to_s   # safe: only digits and operators remain
rescue StandardError => e
  "Error: #{e.message}"
end
```

### Using AgentFS inside a tool

```ruby
Zuzu::ToolRegistry.register(
  'save_note',
  'Save a note to the AgentFS virtual filesystem.',
  {
    type: 'object',
    properties: {
      title:   { type: 'string' },
      content: { type: 'string' }
    },
    required: %w[title content]
  }
) do |args, fs|
  path = "/notes/#{args['title'].downcase.gsub(/\s+/, '_')}.txt"
  fs.write_file(path, args['content'])
  "Saved note to #{path}"
end
```

### Using the KV store for persistent state

```ruby
Zuzu::ToolRegistry.register(
  'remember',
  'Store a fact for future recall.',
  {
    type: 'object',
    properties: {
      key:   { type: 'string' },
      value: { type: 'string' }
    },
    required: %w[key value]
  }
) do |args, fs|
  fs.kv_set(args['key'], args['value'])
  "Remembered: #{args['key']} = #{args['value']}"
end
```

### Tool block rules

- Block signature is always `|args, fs|` (use `_args` or `_fs` if unused)
- `args` keys are **strings** (JSON-parsed): `args['name']` not `args[:name]`
- Return value is converted to String — keep it short and informative
- Raise or return an error string on failure — do not let exceptions propagate silently
- Tools are executed synchronously in the agent loop thread (not the UI thread)

---

## Customising the system prompt

```ruby
Zuzu.configure do |c|
  c.system_prompt_extras = <<~EXTRA
    You are a personal assistant for a Ruby developer named Alex.
    Always use metric units.
    When writing code examples, prefer Ruby unless asked otherwise.
    Never discuss competitor products.
  EXTRA
end
```

The agent's full system prompt is assembled at runtime as:
```
BASE_PROMPT
  + list of all registered tools (auto-generated from ToolRegistry)
  + system_prompt_extras (if set)
```

---

## AgentFS API reference

AgentFS is a sandboxed SQLite virtual filesystem. The agent can only
access files here — never the host machine's filesystem.

### File operations

```ruby
fs.write_file('/path/to/file.txt', 'content')  # create or overwrite, returns true
fs.read_file('/path/to/file.txt')              # returns String or nil if not found
fs.list_dir('/')                               # returns Array of entry names
fs.list_dir('/subdir')                         # names only, not full paths
fs.mkdir('/new/directory')                     # returns true, false if exists
fs.delete('/path/to/file.txt')                 # returns true, false if not found
fs.exists?('/path/to/file.txt')                # returns true/false
fs.stat('/path/to/file.txt')
# returns: { 'id'=>1, 'type'=>'file', 'size'=>42,
#             'created_at'=><ms>, 'updated_at'=><ms> }
# returns nil if not found
# type is 'file' or 'dir'
```

### Key-value store

```ruby
fs.kv_set('last_city', 'Tokyo')
fs.kv_get('last_city')           # → 'Tokyo' or nil
fs.kv_delete('last_city')
fs.kv_list('prefix_')            # → [{'key'=>'...','value'=>'...'}]
```

### Direct SQLite access (advanced)

```ruby
store = Zuzu::Store.new   # or access via fs.store
store.execute("INSERT INTO ...", [param1, param2])
store.query_all("SELECT * FROM kv_store WHERE key LIKE ?", ['user_%'])
store.query_one("SELECT value FROM kv_store WHERE key = ?", ['setting'])
# rows are Hashes with string keys
```

---

## Glimmer DSL for SWT — working patterns

This section documents what has been tested and confirmed working on
JRuby 10.0.3.0 + Java 21 macOS. Glimmer DSL has gotchas — follow these patterns.

### Shell layout (the correct full-app pattern)

```ruby
shell {
  grid_layout 1, false          # single column, do not make equal width
  text 'My App'
  size 860, 620

  scrolled_composite(:v_scroll) {
    layout_data(:fill, :fill, true, true)   # fills all available space
    text(:multi, :read_only, :wrap) {
      background :white
      font name: 'Monospace', height: 13
    }
  }

  composite {
    layout_data(:fill, :fill, true, false)  # false = don't grab vertical space
    grid_layout 3, false                    # columns: input | button | button
    text(:border) {
      layout_data(:fill, :fill, true, false)
    }
    button { text 'Send' }
    button { text 'Other' }
  }
}
```

### layout_data argument form (always use this)

```ruby
layout_data(:fill, :fill, true, false)
# args: (h_alignment, v_alignment, grab_excess_horizontal, grab_excess_vertical)
# :fill  = fill available space
# :left, :right, :center, :beginning, :end  = alignment options
# grab_excess_vertical: true = widget expands vertically. Use false for input rows.
```

### layout_data block form — BROKEN, do not use

```ruby
# This throws InvalidKeywordError on JRuby 10 + Glimmer DSL SWT 4.30:
layout_data {
  height_hint 28    # DO NOT USE
  width_hint 200    # DO NOT USE
}
```

### Updating the chat display

```ruby
# Always append, never replace (unless clearing):
current = @chat_display.swt_widget.get_text
@chat_display.swt_widget.set_text(current + "\n\nAssistant: " + response)
@chat_display.swt_widget.set_top_index(@chat_display.swt_widget.get_line_count)
```

### Opening a secondary window (Admin Panel pattern)

```ruby
def open_settings_panel
  panel = shell {
    text 'Settings'
    minimum_size 400, 300
    grid_layout 1, false

    label { text 'Settings Panel'; font height: 12, style: :bold }

    button {
      layout_data(:fill, :fill, true, false)
      text 'Do Something'
      on_widget_selected { perform_action }
    }
  }
  panel.open
end
```

### Thread safety — mandatory rule

All SWT widget operations MUST happen on the SWT thread.
Always wrap UI updates from background threads in `async_exec`:

```ruby
# CORRECT — LLM call on background thread, UI update on SWT thread:
Thread.new do
  result = @agent.process(user_input)
  async_exec { add_bubble(:assistant, result) }
end

# WRONG — will crash or produce unpredictable behaviour:
Thread.new do
  result = @agent.process(user_input)
  @chat_display.swt_widget.set_text(result)   # never do this
end
```

### Data binding for text input

```ruby
attr_accessor :user_input   # declare in the class

text(:border) {
  text <=> [self, :user_input]   # two-way binding
  on_key_pressed do |e|
    send_message if e.character == 13   # Enter key
  end
}
```

### Font and color

```ruby
font name: 'Monospace', height: 13
font height: 12, style: :bold          # styles: :bold, :italic, :normal
background :white                      # named color
background rgb(225, 235, 255)          # custom RGB
foreground rgb(66, 133, 244)
```

### What does NOT work — avoid these

| Pattern | Problem |
|---------|---------|
| `sash_form` | Right pane is invisible on macOS — use plain `composite` instead |
| `layout_data { height_hint N }` | `InvalidKeywordError` — use argument form |
| `shell.setSize(w, h)` inside `body {}` | Use `size w, h` DSL method |
| Calling widget methods outside `async_exec` from a Thread | SWT thread violation, crashes |
| `require 'glimmer-dsl-swt'` in app.rb | Already loaded by Zuzu — causes conflicts |

---

## Extending the UI

### Changing app name and window size

```ruby
Zuzu.configure do |c|
  c.app_name      = 'My Custom Assistant'
  c.window_width  = 1024
  c.window_height = 768
end
```

### Extending Zuzu::App for deeper customisation

To override helper methods (e.g. `open_admin_panel`), **reopen `Zuzu::App` directly** —
do NOT subclass it. Subclassing causes Glimmer to raise
`Invalid custom widget for having no body!` because `body`, `before_body`, and
`after_body` are DSL class-level declarations that are not inherited by subclasses.

**Correct pattern — reopen the class:**

```ruby
module Zuzu
  class App
    # Override any private helper method here.
    # @store, @fs, @agent etc. are all available (set up by before_body).
    def open_admin_panel
      panel = shell {
        text 'My Custom Panel'
        minimum_size 400, 400
        grid_layout 1, false
        # ... your widgets here
      }
      panel.open
    end

    private

    def my_helper
      # additional private methods are fine here too
    end
  end
end

Zuzu::App.launch!(use_llamafile: true)  # always launch on Zuzu::App, not a subclass
```

**Why not subclass?** `before_body`, `after_body`, and `body` are Glimmer DSL
declarations stored at the class level. A subclass has none of them, so Glimmer
refuses to instantiate it with "no body" error. Reopening `Zuzu::App` avoids
this entirely while still giving full access to all instance variables.

---

## LLM and agent behaviour

### How tool calling works

The agent uses prompt-based tool calling — no native function-calling API.
Any instruction-following model works (not just models with `tool_calls` support).

1. Agent builds system prompt listing all registered tools
2. Sends `[{system}, {user message}]` to llamafile
3. Model outputs `<zuzu_tool_call>{"name":"...","args":{...}}</zuzu_tool_call>`
4. Agent parses tag, calls `ToolRegistry.execute(name, args, fs)`
5. Result injected as `<zuzu_tool_result>...</zuzu_tool_result>` user message
6. Loops up to 10 times; stops when response has no tool call tags
7. Final plain-text response stored in Memory and shown in UI

### Conversation history

Memory is persisted in SQLite but **not injected into the LLM context**.
This is intentional — prior non-tool responses cause models to skip tool use.
Each request is: `[system_prompt, current_user_message]`.

### Loop detection

If the agent calls the same tool with the same args more than twice,
the loop is broken and the model is told to give its final answer.
Log line: `[zuzu] loop detected for <tool_name>, breaking`

### LLM not calling tools — common causes

1. `system_prompt_extras` text accidentally overrides the tool-use rules
2. Model quality — smaller/quantised models follow instructions less reliably
3. User message too ambiguous — tools need clear intent to be triggered
4. Tool description unclear — descriptions are shown verbatim to the model

---

## Packaging

### Step 1 — Build the JAR

```bash
bundle exec zuzu package
```

- Creates `<app-directory>.jar` in the current directory
- Warbler auto-detects `bin/app` as the executable entry point (created automatically)
- `models/` directory is NOT bundled — place model files next to the jar at runtime
- Path resolution: `__dir__` inside a jar returns `uri:classloader:/` —
  app.rb already handles this with the `base` variable pattern

Run the jar (requires Java 21+ installed):
```bash
java -XstartOnFirstThread -jar my_app.jar   # macOS (SWT requires first thread)
java -jar my_app.jar                        # Linux / Windows
```

### Step 2 — Build a native installer (optional, no Java required for users)

After the JAR is built, `zuzu package` prompts:

```
Bundle into a self-contained native executable? (no Java required for users) [y/N]:
```

Type `y`. Zuzu uses **jpackage** (included with JDK 21+) to bundle a minimal JRE
via jlink and produce a platform-native installer:

| Platform | Output in `dist/` |
|----------|-------------------|
| macOS | `.dmg` — drag-to-Applications `.app` bundle |
| Linux | `.deb` package |
| Windows | `.exe` installer |

The model file cannot be bundled (too large). Zuzu injects the model filename as
the `-Dzuzu.model` JVM property. At runtime, `Zuzu::Config#llamafile_path` resolves
it from the platform user-data directory automatically:

```
macOS:   ~/Library/Application Support/<AppName>/models/<model>.llamafile
Linux:   ~/.local/share/<AppName>/models/<model>.llamafile
Windows: %APPDATA%\<AppName>\models\<model>.llamafile
```

`zuzu package` prints the exact path — tell your users to place the model there
before launching the installed app.

---

## Debugging

### Check the LLM is running

```bash
curl http://127.0.0.1:8080/v1/models
```

### Watch agent tool calls in real time

Tool calls and results are printed to stderr:
```
[zuzu] tool current_time({}) => 2025-01-15 14:32:00 PST
[zuzu] tool write_file({"path"=>"/notes/x.txt","content"=>"..."}) => Written 42 bytes
```

### Open IRB with the full framework loaded

```bash
bundle exec zuzu console
store = Zuzu::Store.new
fs    = Zuzu::AgentFS.new(store)
fs.write_file('/test.txt', 'hello')
fs.read_file('/test.txt')   # => "hello"
```

### Inspect the SQLite database directly

```bash
sqlite3 .zuzu/zuzu.db
.tables          # fs_inodes, fs_dentries, kv_store, messages, tool_calls
SELECT * FROM messages ORDER BY id DESC LIMIT 5;
SELECT key, value FROM kv_store;
```

### llamafile startup log

```bash
tail -f models/llama.log
```

### Common errors

| Error | Cause | Fix |
|-------|-------|-----|
| `llamafile not found: ...` | Model path wrong or file missing | Check `c.llamafile_path` and `chmod +x` |
| `LoadError: no such file -- zuzu` | Not running with bundler | Use `bundle exec zuzu start` |
| Blank/invisible UI widgets | Wrong `layout_data` (grab_excess_vertical=true) | Change last arg to `false` |
| `InvalidKeywordError` in layout | Block-form `layout_data { }` used | Use argument form `layout_data(:fill, :fill, true, false)` |
| Agent never calls tools | History contamination or bad prompt | Check `system_prompt_extras` isn't overriding rules |
| `SSL certificate verify failed` | JRuby uses Java SSL store | `verify_mode: OpenSSL::SSL::VERIFY_NONE` (already set in http_get) |
| `SWT thread access violation` | Widget update from background thread | Wrap in `async_exec { }` |

---

## File structure of a Zuzu app

```
my_app/
├── app.rb          # ← your main file: configure + tools + launch
├── Gemfile         # gem "zuzu"
├── warble.rb       # packaging config (auto-generated by zuzu package)
├── bin/
│   └── app         # thin launcher for warbler (auto-generated)
├── models/
│   └── *.llamafile  # local LLM binaries — download separately, not in git
└── .zuzu/
    └── zuzu.db     # SQLite database — not in git
```

---

## What the Zuzu gem provides (do not reimplement)

- `Zuzu::App` — Glimmer SWT desktop window
- `Zuzu::Agent` — ReAct loop with `<zuzu_tool_call>` parsing
- `Zuzu::AgentFS` — SQLite virtual filesystem
- `Zuzu::Memory` — conversation history
- `Zuzu::Store` — JDBC SQLite query layer
- `Zuzu::LlmClient` — HTTP client for llamafile API
- `Zuzu::LlamafileManager` — llamafile subprocess lifecycle
- `Zuzu::ToolRegistry` — tool registration and execution
- Built-in tools: `read_file`, `write_file`, `list_directory`, `run_command`, `http_get`
- Channels: `InApp` (desktop GUI), `WhatsApp` (opt-in via `c.channels = ['whatsapp']`)

All of the above is loaded automatically by `require 'zuzu'` in `app.rb`.
