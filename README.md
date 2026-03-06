# Zuzu

**Build AI-native desktop apps that run entirely on the user's machine.**

Every application you install on an operating system does the same fundamental thing: it translates human intent into OS system calls. A text editor writes bytes to disk. A browser opens network connections. At its core, every installed app is an orchestrator of operating system capabilities.

LLMs are simply a more expressive interface for exactly that orchestration. Zuzu is a framework built on this premise — for developers who want to ship installable, AI-native desktop apps where the intelligence runs on the user's hardware, not in a data center.

**Why does this matter?**

- **Privacy by architecture.** The agent operates inside AgentFS — a sandboxed virtual filesystem backed by a single SQLite file. It cannot touch the host OS unless you explicitly open that door. There is no network call to make, no token to rotate, no terms of service that changes next quarter.

- **Deployable like software, not like a service.** Package your app as a single `.jar`. Users pay, download, double-click, and run. No Docker. No cloud subscription. No infrastructure to maintain. The JVM handles cross-platform distribution the way it has for 30 years.

- **Built for regulated environments.** A therapist keeping session notes, an auditor running confidential analysis, a corporate team in a restricted environment — these are exactly the users who benefit most from powerful AI but are currently blocked by cloud dependency. A bundled LLM in a self-contained Java application needs no external approval to run.

- **Developer experience that matches how software is actually built today.** `zuzu new my_app` scaffolds a project pre-wired for Claude Code: CLAUDE.md, skills for `/setup`, `/add-tool`, `/customize`, and `/debug` — all enforcing Zuzu's patterns. Open the folder, start your coding agent, describe what you want to build.

→ [Why Zuzu exists](docs/why.md) · [Quick Demo](https://raw.githubusercontent.com/parolkar/zuzu/refs/heads/main/docs/demo/zuzu_quick_demo_01.mp4)

<video src="https://raw.githubusercontent.com/parolkar/zuzu/refs/heads/main/docs/demo/zuzu_quick_demo_01.mp4" controls width="100%"></video>
[Quick Demo](https://raw.githubusercontent.com/parolkar/zuzu/refs/heads/main/docs/demo/zuzu_quick_demo_01.mp4)

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

`bin/setup` installs Java 21, JRuby 10.0.3.0, and all gem dependencies
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
  c.app_name = 'My Assistant'
  # Works both when run directly and from a packaged .jar
  base = __dir__.to_s.start_with?('uri:classloader:') ? Dir.pwd : __dir__
  c.llamafile_path = File.join(base, 'models', 'llava-v1.5-7b-q4.llamafile')
  c.db_path        = File.join(base, '.zuzu', 'zuzu.db')
  c.port           = 8080
end
```

Launch:

```bash
bundle exec zuzu start
```

You'll see a native desktop chat window. The llamafile model starts automatically
in the background. Click **Admin Panel** to browse the AgentFS virtual filesystem.

---

## Manual Setup

If `bin/setup` doesn't suit your workflow, follow these steps.

### 1. Install Java 21+

**macOS (Homebrew — recommended):**

```bash
brew install --cask temurin@21
```

Temurin is the Eclipse/Adoptium OpenJDK distribution. The cask sets up
`JAVA_HOME` automatically — no manual PATH changes needed.

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

### 2. Install JRuby 10.0.3.0 via rbenv

```bash
# Install rbenv if needed
brew install rbenv ruby-build   # macOS
# or: https://github.com/rbenv/rbenv#installation

rbenv install jruby-10.0.3.0
rbenv local jruby-10.0.3.0
ruby -v
# → jruby 10.0.3.0 (ruby 3.x.x) ...
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

Package your app as a standalone Java archive with a single command:

```bash
bundle exec zuzu package
```

This auto-installs Warbler if needed, generates the necessary launcher, and
produces a `.jar` named after your app directory. Run it with:

```bash
java -XstartOnFirstThread -jar my_app.jar   # macOS
java -jar my_app.jar                        # Linux / Windows
```

> **Note:** Place your llamafile model in a `models/` directory alongside the
> `.jar` — models are not bundled into the archive.

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
zuzu package         Package the app as a standalone .jar
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
