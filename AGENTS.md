# AGENTS.md — Zuzu Codebase Guide for AI Assistants

This file helps AI coding assistants (Copilot, Cursor, Cody, etc.)
understand the Zuzu project structure and conventions.

## What Is Zuzu?

Zuzu is a JRuby desktop framework for building local-first AI assistants.
It combines Glimmer DSL for SWT (native GUI), JDBC SQLite (storage),
and llamafile (local LLM inference) into a single gem.

## Tech Stack

| Layer      | Technology                  |
|------------|-----------------------------|
| Runtime    | JRuby 10.0.4.0 (Java 21+)  |
| GUI        | Glimmer DSL for SWT 4.30    |
| Database   | SQLite via jdbc-sqlite3     |
| LLM        | llamafile (OpenAI-compat)   |
| Packaging  | Warbler (jar/war)           |

## Project Layout

```
zuzu/
├── lib/zuzu/
│   ├── config.rb           # Zuzu.configure { |c| ... }
│   ├── store.rb            # JDBC SQLite query layer
│   ├── agent_fs.rb         # Virtual filesystem + KV store
│   ├── memory.rb           # Conversation history
│   ├── llm_client.rb       # HTTP client for llamafile
│   ├── llamafile_manager.rb # Subprocess lifecycle
│   ├── tool_registry.rb    # Register / execute agent tools
│   ├── agent.rb            # ReAct loop
│   ├── app.rb              # Glimmer SWT desktop shell
│   ├── tools/              # Built-in tools (file, shell, web)
│   └── channels/           # Message channels (in_app, whatsapp)
├── bin/zuzu                # CLI entry point
├── templates/app.rb        # Scaffold template for `zuzu new`
└── app.rb                  # Phase 1 standalone reference
```

## Key Patterns

1. **Store** is the single JDBC connection wrapper. AgentFS and Memory
   both accept a Store instance — never create raw JDBC connections.

2. **GUI layout** uses `row_layout(:vertical)` inside `scrolled_composite`.
   Never use `expand_horizontal`/`expand_vertical` on scrolled_composite —
   it causes zero-height collapse on SWT.

3. **Chat bubbles** are `label(:wrap)` with `layout_data { width 500 }`.
   After adding a bubble, call `layout(true, true)` on both the chat
   panel and the body root, then `set_origin` to auto-scroll.

4. **Agent tools** are registered via `ToolRegistry.register(name, desc, schema, &block)`.
   The block receives `(args_hash, agent_fs)`.

5. **macOS SWT** requires `JRUBY_OPTS="-J-XstartOnFirstThread"`.

## Conventions

- `frozen_string_literal: true` everywhere.
- No meta-programming. Explicit is better.
- Keep each file under ~200 lines.
- All database access goes through `Store#execute` / `Store#query_all`.
- SQLite schemas use `CREATE TABLE IF NOT EXISTS` for idempotency.
