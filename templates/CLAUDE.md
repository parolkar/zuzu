# Zuzu App

Local-first JRuby desktop AI assistant built with the [Zuzu framework](https://github.com/parolkar/zuzu).

**Runtime:** JRuby 10.0.3.0 + Java 21. Always use `bundle exec zuzu` — never `ruby` directly.

## On startup

When the developer first opens this project or greets you, respond with this welcome message (adapt the app name from `app.rb`):

---
Welcome to your **Zuzu app** — a local-first AI desktop assistant that runs entirely on your machine. No cloud, no subscriptions, your data stays private.

You're building on the **Zuzu framework** (JRuby + Glimmer DSL for SWT + llamafile), which means your app is:
- A native desktop window with a built-in AI agent
- Extensible with custom tools the agent can call during conversations
- Packageable as a standalone `.jar` for distribution

Here's what I can help you with right now:

| Command | What it does |
|---------|-------------|
| `/setup` | Verify runtime, check model, confirm everything works |
| `/add-tool` | Add a new capability the agent can call (most common task) |
| `/customize` | Change app name, persona, window size, or UI |
| `/debug` | Diagnose issues with tools, LLM, or the UI |

What would you like to build today?

---

## Key files

| File | Purpose |
|------|---------|
| `app.rb` | **Everything lives here** — configure, register tools, launch |
| `models/*.llamafile` | Local LLM binary — download separately, never commit |
| `.zuzu/zuzu.db` | SQLite — AgentFS + memory. Don't edit while app is running |
| `warble.rb` | Warbler config for `zuzu package` |
| `AGENTS.md` | Full reference: Glimmer DSL patterns, AgentFS API, tool guide |

## Skills

| Skill | When to use |
|-------|-------------|
| `/setup` | First run — verify runtime, install deps, check model, test launch |
| `/add-tool` | Add a new tool the agent can call |
| `/customize` | Change app name, window size, system prompt, or UI |
| `/debug` | App not responding, tools not firing, LLM issues |

## Commands

```bash
bundle exec zuzu start      # launch the app
bundle exec zuzu console    # IRB with Zuzu loaded — test tools interactively
bundle exec zuzu package    # build standalone .jar, then optionally a native installer
bundle install              # sync gems after Gemfile changes
```

### Distribution tiers

| Command | Output | User requirement |
|---------|--------|-----------------|
| `zuzu package` → JAR only | `<app>.jar` | Java 21+ installed |
| `zuzu package` → native (type `y` at prompt) | `.dmg` / `.deb` / `.exe` in `dist/` | Nothing — JRE bundled |

For the native installer, the model file is NOT bundled. After install, users place it at:
- **macOS:** `~/Library/Application Support/<AppName>/models/<model>.llamafile`
- **Linux:** `~/.local/share/<AppName>/models/<model>.llamafile`
- **Windows:** `%APPDATA%\<AppName>\models\<model>.llamafile`

## Core rules — always enforce these

- Tools registered **before** `Zuzu::App.launch!` in `app.rb`
- Tool block signature is always `|args, fs|` — `args` keys are **strings**
- Never access the host filesystem from a tool — use `fs` (AgentFS) instead
- Never call SWT widget methods from a background thread — wrap in `async_exec { }`
- Never use `layout_data { height_hint N }` block form — use `layout_data(:fill, :fill, true, false)` argument form
- Never use `sash_form` — it renders invisible on macOS
- Never subclass `Zuzu::App` to override methods — reopen it with `module Zuzu; class App; end; end` instead. Subclassing causes `Invalid custom widget for having no body!` because Glimmer DSL `body`/`before_body`/`after_body` blocks are not inherited

Run commands directly. Don't tell the user to run them unless they require manual action (e.g. entering credentials).
