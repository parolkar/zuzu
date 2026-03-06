# Zuzu

**Local-first agentic desktop apps with JRuby.**

Zuzu is a framework for building privacy-respecting AI desktop assistants that
run entirely on your machine. No cloud APIs required — your data stays local.

<video src="https://raw.githubusercontent.com/parolkar/zuzu/refs/heads/main/docs/demo/zuzu_quick_demo_01.mp4" controls width="100%"></video>

| Component | Technology |
|-----------|------------|
| Runtime | JRuby 10.0.3.0 (Java 21+) |
| GUI | Glimmer DSL for SWT |
| Database | SQLite via JDBC |
| LLM | llamafile (local inference) |
| Packaging | Warbler (.jar / .war) |

## Quick Start

### Prerequisites

- **macOS** or **Linux** (Windows support is planned)
- **Java 21+**
- **rbenv** (recommended) or any JRuby version manager

### One-Command Setup

```bash
git clone https://github.com/parolkar/zuzu.git
cd zuzu
bin/setup
```

`bin/setup` installs Java 21, JRuby 10.0.4.0, and all gem dependencies
automatically. If you prefer manual setup, see [Manual Setup](#manual-setup)
below.

### Create Your First App

When you run `bin/zuzu new` from the source tree, it automatically detects
dev mode and points the scaffolded app's Gemfile at your local checkout
(no published gem needed).

```bash
bin/zuzu new my_assistant
cd my_assistant
bundle install
```

Download a llamafile model:

```bash
mkdir -p models
curl -L -o models/llava-v1.5-7b-q4.llamafile \
  https://huggingface.co/Mozilla/llava-v1.5-7b-llamafile/resolve/main/llava-v1.5-7b-q4.llamafile
chmod +x models/llava-v1.5-7b-q4.llamafile
```

Edit `app.rb` to point at your model:

```ruby
Zuzu.configure do |c|
  c.app_name       = 'My Assistant'
  c.llamafile_path = File.expand_path('models/llava-v1.5-7b-q4.llamafile', __dir__)
  c.db_path        = File.expand_path('.zuzu/zuzu.db', __dir__)
  c.port           = 8080
end
```

Launch:

```bash
# macOS (SWT requires first-thread access):
JRUBY_OPTS="-J-XstartOnFirstThread -J--enable-native-access=ALL-UNNAMED" bundle exec ruby app.rb

# Linux:
JRUBY_OPTS="-J--enable-native-access=ALL-UNNAMED" bundle exec ruby app.rb
```

You'll see a native desktop window with a file browser on the left and a chat
interface on the right. The llamafile model starts automatically in the
background.

---

## Manual Setup

If `bin/setup` doesn't suit your workflow, follow these steps.

### 1. Install Java 21+

**macOS (Homebrew):**

```bash
brew install openjdk@21
```

Add to your shell profile (`~/.zshrc` or `~/.bash_profile`):

```bash
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
export PATH="$JAVA_HOME/bin:$PATH"
```

**macOS (SDKMAN):**

```bash
curl -s https://get.sdkman.io | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install java 21-tem
```

**Ubuntu / Debian:**

```bash
sudo apt-get update
sudo apt-get install openjdk-21-jdk
```

Verify:

```bash
java -version
# → openjdk version "21.x.x" ...
```

### 2. Install JRuby 10.0.4.0 via rbenv

```bash
# Install rbenv if needed
brew install rbenv ruby-build   # macOS
# or: https://github.com/rbenv/rbenv#installation

rbenv install jruby-10.0.4.0
rbenv local jruby-10.0.4.0
ruby -v
# → jruby 10.0.4.0 (ruby 3.x.x) ...
```

### 3. Install Gems

```bash
gem install bundler
bundle install
```

---

## Architecture

```
┌────────────────────────────────────────────────────┐
│                   Zuzu App (SWT)                   │
│  ┌──────────┐  ┌──────────────────────────────┐    │
│  │ AgentFS  │  │       Chat Interface         │    │
│  │  (files) │  │                              │    │
│  │          │  │  User: How do I ...          │    │
│  │  + docs/ │  │  Zuzu: Let me check ...      │    │
│  │    a.txt │  │                              │    │
│  └──────────┘  └──────────────────────────────┘    │
│                ┌──────────────────────────────┐    │
│                │ [  Type a message...  ] [Send]│    │
│                └──────────────────────────────┘    │
└──────────────────────────┬─────────────────────────┘
                           │
              ┌────────────▼────────────┐
              │      Agent (ReAct)      │
              │   ┌─────┐ ┌─────────┐  │
              │   │Tools│ │ Memory  │  │
              │   └──┬──┘ └────┬────┘  │
              └──────┼─────────┼───────┘
                     │         │
              ┌──────▼─────────▼───────┐
              │    SQLite (JDBC)       │
              │  - fs_inodes/dentries  │
              │  - messages            │
              │  - kv_store            │
              │  - tool_calls          │
              └────────────────────────┘
                           │
              ┌────────────▼────────────┐
              │   llamafile (local LLM) │
              │   OpenAI-compat API     │
              │   http://127.0.0.1:8080 │
              └─────────────────────────┘
```

### Project Structure

```
zuzu/
├── lib/zuzu/
│   ├── config.rb             # Zuzu.configure { |c| ... }
│   ├── store.rb              # JDBC SQLite — single connection wrapper
│   ├── agent_fs.rb           # Virtual filesystem + KV store + audit log
│   ├── memory.rb             # Conversation history
│   ├── llm_client.rb         # HTTP client for llamafile
│   ├── llamafile_manager.rb  # Subprocess lifecycle
│   ├── tool_registry.rb      # Register / execute agent tools
│   ├── agent.rb              # ReAct loop (think → act → observe)
│   ├── app.rb                # Glimmer SWT desktop shell
│   ├── tools/
│   │   ├── file_tool.rb      # read_file, write_file, list_directory
│   │   ├── shell_tool.rb     # run_command (allowlisted)
│   │   └── web_tool.rb       # http_get
│   └── channels/
│       ├── base.rb           # Abstract channel interface
│       ├── in_app.rb         # Desktop GUI (default)
│       └── whatsapp.rb       # WhatsApp Cloud API webhook
├── bin/
│   ├── zuzu                  # CLI: new / start / console / version
│   └── setup                 # One-command bootstrap
├── templates/
│   └── app.rb                # Scaffold template for `zuzu new`
├── models/                   # Place llamafile models here
├── Gemfile
├── zuzu.gemspec
├── Rakefile
├── warble.rb                 # Warbler config for .jar packaging
└── app.rb                    # Phase 1 standalone reference
```

---

## Usage Guide

### Custom Tools

Register tools that the agent can call during conversations:

```ruby
Zuzu::ToolRegistry.register(
  'lookup_weather',
  'Get current weather for a city.',
  {
    type: 'object',
    properties: { city: { type: 'string' } },
    required: ['city']
  }
) do |args, agent_fs|
  # Your logic here — call an API, read a file, etc.
  "Weather in #{args['city']}: 22°C, sunny"
end
```

The agent's ReAct loop will automatically discover and call your tools when
relevant to the user's question.

### WhatsApp Channel

Enable WhatsApp so users can chat with your agent via their phone:

```ruby
Zuzu.configure do |c|
  c.channels = ['whatsapp']
end
```

Set environment variables:

```bash
export WHATSAPP_TOKEN="your_cloud_api_token"
export WHATSAPP_PHONE_ID="your_phone_number_id"
export WHATSAPP_PORT=9292   # optional, defaults to 9292
```

The WhatsApp channel starts a WEBrick webhook server that receives messages
from the WhatsApp Cloud API and replies using the same agent.

### Virtual Filesystem (AgentFS)

The agent operates in a sandboxed SQLite-backed filesystem:

```ruby
store = Zuzu::Store.new
fs    = Zuzu::AgentFS.new(store)

fs.write_file('/notes/todo.txt', 'Buy groceries')
fs.read_file('/notes/todo.txt')    # → "Buy groceries"
fs.list_dir('/notes')              # → ["todo.txt"]
fs.mkdir('/docs')
fs.exists?('/notes/todo.txt')      # → true

# Key-value store
fs.kv_set('last_query', 'weather in Tokyo')
fs.kv_get('last_query')            # → "weather in Tokyo"
```

### Packaging as .jar

Use Warbler to create a standalone Java archive:

```bash
gem install warbler
warble jar
java -XstartOnFirstThread -jar zuzu-app.jar   # macOS
java -jar zuzu-app.jar                        # Linux
```

---

## Configuration Reference

```ruby
Zuzu.configure do |c|
  c.app_name       = 'My Agent'           # Window title
  c.llamafile_path = 'models/llava-v1.5-7b-q4.llamafile'   # Path to llamafile binary
  c.db_path        = '.zuzu/zuzu.db'      # SQLite database location
  c.port           = 8080                  # llamafile API port
  c.model          = 'LLaMA_CPP'          # Model identifier
  c.channels       = ['whatsapp']          # Extra channels to enable
  c.log_level      = :info                 # :debug, :info, :warn, :error
  c.window_width   = 860                   # Window width in pixels
  c.window_height  = 620                   # Window height in pixels
end
```

---

## CLI Reference

```
zuzu new APP_NAME    Scaffold a new Zuzu application
zuzu start           Launch the Zuzu app in the current directory
zuzu console         Open an IRB session with Zuzu loaded
zuzu version         Print the Zuzu version
zuzu help            Show this message
```

---

## Troubleshooting

### macOS: "SWT main thread" error

SWT on macOS requires the main thread. Always launch with:

```bash
JRUBY_OPTS="-J-XstartOnFirstThread -J--enable-native-access=ALL-UNNAMED" bundle exec ruby app.rb
```

### llamafile won't start

- Ensure the file is executable: `chmod +x models/your-model.llamafile`
- Check `models/llama.log` for errors.
- Verify port 8080 isn't already in use: `lsof -i :8080`

### "java.lang.ClassNotFoundException: org.sqlite.JDBC"

Run `bundle install` to ensure `jdbc-sqlite3` is installed. The gem must be
loaded before any database access.


---

## Philosophy

- **Local-first.** Your data never leaves your machine.
- **Minimal code.** The entire framework is ~800 lines of Ruby.
- **No Docker.** Just Java, JRuby, and a single SQLite file.
- **Channels built in.** Every app gets in-app chat and optional WhatsApp.
- **Tools are Ruby blocks.** No YAML configs, no DSL ceremonies.

---

## License

MIT — see [LICENSE](LICENSE).

## Author(s)

**Abhishek Parolkar**
- GitHub: [@parolkar](https://github.com/parolkar)
