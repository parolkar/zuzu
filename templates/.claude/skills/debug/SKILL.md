---
name: debug
description: Diagnose and fix Zuzu app issues. Use when the app won't start, the agent isn't responding, tools aren't being called, the LLM seems stuck, or the UI is broken. Runs a systematic health check and fixes what it finds.
---

# Debug Zuzu App

Run each check in order. Fix problems as they're found — don't present a list and ask the user to fix them.

## Check 1 — Ruby code syntax

```bash
bundle exec ruby -e "require 'zuzu'; load 'app.rb'" 2>&1
```

- If syntax error or LoadError: fix the error in `app.rb`, re-run, continue.
- If clean: continue.

## Check 2 — Registered tools

```bash
bundle exec ruby -e "
require 'zuzu'
load 'app.rb' rescue nil
tools = Zuzu::ToolRegistry.tools
if tools.empty?
  puts 'WARNING: No tools registered'
else
  tools.each { |t| puts '  - ' + t.name + ': ' + t.description }
end
" 2>&1
```

- No tools: check `app.rb` — registrations must be before `Zuzu::App.launch!`. Fix and retry.
- Tools listed: continue.

## Check 3 — Model file

Read `app.rb` to find `c.llamafile_path`. Then:

```bash
ls -lh <model_path> 2>&1
```

- File not found: tell the user they need to download the model to the `models/` directory.
- File exists but not executable: `chmod +x <model_path>` — do this automatically.
- File ok: continue.

## Check 4 — Is llamafile running?

```bash
curl -s --max-time 3 http://127.0.0.1:8080/v1/models 2>&1
```

- Connection refused / timeout: llamafile isn't running. The app starts it — check the log:

```bash
ls models/*.log 2>/dev/null && tail -30 models/*.log 2>/dev/null || echo "No log file found"
```

Common causes:
- Model file not found (covered above)
- Port 8080 already in use: `lsof -i :8080` — if another process, kill it or change port in `app.rb`
- Model too large for available RAM — check `tail -5 models/llama.log` for OOM errors

- Returns JSON with models: llamafile is running. Continue.

## Check 5 — LLM responds to a basic chat

```bash
curl -s --max-time 30 http://127.0.0.1:8080/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"LLaMA_CPP","messages":[{"role":"user","content":"reply with the single word: OK"}],"temperature":0.1}' \
  2>&1 | head -5
```

- Returns JSON with `OK` in choices: LLM is healthy. Continue.
- Times out: model is still loading. Wait 30s, retry.
- Error: check `models/llama.log` for details.

## Check 6 — Tool call parsing (agent loop)

```bash
bundle exec zuzu console 2>/dev/null <<'EOF'
store  = Zuzu::Store.new
fs     = Zuzu::AgentFS.new(store)
memory = Zuzu::Memory.new(store)
llm    = Zuzu::LlmClient.new
agent  = Zuzu::Agent.new(agent_fs: fs, memory: memory, llm: llm)
result = agent.process('What time is it? Use the current_time tool if available, otherwise just say hello.')
puts "Agent response: #{result}"
EOF
```

- Response contains sensible text: agent loop works.
- `Max iterations reached`: model isn't calling tools. See "Agent not calling tools" below.
- Error: read the traceback, fix the root cause.

## Check 7 — Recent tool call history

```bash
bundle exec ruby -e "
require 'zuzu'
store = Zuzu::Store.new
rows = store.query_all('SELECT tool_name, input, output, started_at FROM tool_calls ORDER BY started_at DESC LIMIT 10')
if rows.empty?
  puts 'No tool calls recorded yet'
else
  rows.each { |r| puts r['tool_name'] + ' → ' + r['output'].to_s[0,80] }
end
" 2>&1
```

- Shows recent calls: tools are firing.
- Empty: either app hasn't been used yet, or tools aren't being called.

## Check 8 — AgentFS health

```bash
bundle exec ruby -e "
require 'zuzu'
store = Zuzu::Store.new
fs    = Zuzu::AgentFS.new(store)
fs.write_file('/debug_test.txt', 'hello')
result = fs.read_file('/debug_test.txt')
puts result == 'hello' ? 'AgentFS OK' : 'AgentFS BROKEN: got ' + result.inspect
fs.delete('/debug_test.txt')
" 2>&1
```

- "AgentFS OK": filesystem healthy.
- Error: check that `.zuzu/` directory is writable: `ls -la .zuzu/`

---

## Known issues and fixes

### Agent not calling tools

The most common cause is the model not following the system prompt reliably.

1. **Check the system prompt is being built**: open `bundle exec zuzu console` and run:
   ```ruby
   require 'zuzu'; load 'app.rb' rescue nil
   store = Zuzu::Store.new; fs = Zuzu::AgentFS.new(store); memory = Zuzu::Memory.new(store); llm = Zuzu::LlmClient.new
   agent = Zuzu::Agent.new(agent_fs: fs, memory: memory, llm: llm)
   puts agent.send(:build_system_prompt)
   ```
   Verify your tools appear in the "Available tools:" section.

2. **Check `system_prompt_extras`** — if it contains conflicting instructions (e.g. "never use tools") it can override the base prompt.

3. **Model quality** — llava-v1.5-7b-q4 is a vision model and follows tool-calling instructions inconsistently. Try a more capable model or rephrase your request to more explicitly ask for tool use.

### Blank or invisible UI widgets

Caused by wrong `layout_data`. Check `app.rb` for any subclassed body or UI code:

- `layout_data(:fill, :fill, true, true)` on an input composite → change last arg to `false`
- `layout_data { height_hint N }` → replace with `layout_data(:fill, :center, false, false)`
- `sash_form` → remove and replace with plain `composite`

### SWT thread error / crash on UI update

Wrap all widget updates that happen inside `Thread.new` with `async_exec`:

```ruby
Thread.new do
  result = do_something_slow
  async_exec { @chat_display.swt_widget.set_text(result) }  # ← required
end
```

### Port 8080 already in use

```bash
lsof -i :8080
```

Kill the occupying process, or change `c.port = 8081` in `app.rb` — the LLM client and manager both read from config.

### Database locked

Only one process can write to `.zuzu/zuzu.db` at a time. Ensure only one instance of the app is running.

---

## Summary output

After all checks, tell the user:
- ✅/❌ Ruby syntax
- ✅/❌ Tools registered (list names)
- ✅/❌ Model file
- ✅/❌ LLM running
- ✅/❌ LLM responding
- ✅/❌ AgentFS healthy
- Any fixes applied + next steps
