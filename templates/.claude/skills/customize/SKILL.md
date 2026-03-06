---
name: customize
description: Customize the Zuzu app — change the app name, window size, system prompt persona, or extend the UI. Use when the developer wants to rebrand the app, add personality to the assistant, or make visual/behavioral changes.
---

# Customize Zuzu App

Ask what the developer wants to change, then make the changes directly.

## Step 1 — Understand the request

AskUserQuestion: "What would you like to customize? Choose one or more:
1. App name / window title
2. Window size
3. Assistant persona / system prompt instructions
4. Add a new button or panel to the UI
5. Something else — describe it"

Route to the relevant section below based on the answer.

---

## Route A — App name and window title

Read the current value from `app.rb`:

```ruby
Zuzu.configure do |c|
  c.app_name = 'Current Name'
```

AskUserQuestion: "What should the app be called?"

Edit `app.rb` — update `c.app_name`. Done. Tell the user to restart the app.

---

## Route B — Window size

Read current values (`c.window_width`, `c.window_height`).

AskUserQuestion: "What size should the window be? (e.g. 1024 × 768, 1280 × 800)"

Edit `app.rb`:
```ruby
c.window_width  = 1024
c.window_height = 768
```

Done. Tell the user to restart.

---

## Route C — Assistant persona and system prompt

Read the current `c.system_prompt_extras` from `app.rb` (may be nil/absent).

AskUserQuestion: "Describe the assistant's persona or any extra rules you want it to follow. Examples:
- 'You are a Ruby developer assistant. Always use Ruby in code examples.'
- 'You are a cooking assistant. Only discuss food, recipes, and nutrition.'
- 'Always respond concisely in bullet points.'"

AskUserQuestion: "Should this replace the current instructions or be added to them?"

Edit `app.rb` — set or update `c.system_prompt_extras`:

```ruby
Zuzu.configure do |c|
  # ...
  c.system_prompt_extras = <<~EXTRA
    <the persona instructions here>
  EXTRA
end
```

**Important rules to preserve** — always keep these in `system_prompt_extras` if the developer's text doesn't already cover them:
- Do not override the tool-calling rules (those come from the base prompt automatically)
- Keep instructions concise — the model sees this verbatim on every request

Verify it loads:
```bash
bundle exec ruby -e "require 'zuzu'; load 'app.rb' rescue nil; puts Zuzu.config.system_prompt_extras" 2>&1
```

Done. Tell the user to restart.

---

## Route D — UI: add a button to the Admin Panel

The Admin Panel is the popup window opened by the "Admin Panel" button.
The easiest UI extension is adding a button there.

AskUserQuestion: "What should the button do when clicked?"
AskUserQuestion: "What label should the button have?"

This requires subclassing `Zuzu::App`. Check if `app.rb` already subclasses it.

**If not subclassing yet**, add this pattern to `app.rb` before `Zuzu::App.launch!`:

```ruby
class MyApp < Zuzu::App
  private

  def open_admin_panel
    file_list_widget = nil

    admin = shell {
      text 'Admin Panel'
      minimum_size 380, 500
      grid_layout 1, false

      label {
        layout_data(:fill, :fill, true, false)
        text 'AgentFS — Virtual File Browser'
        font height: 12, style: :bold
      }

      file_list_widget = list(:single, :v_scroll, :border) {
        layout_data(:fill, :fill, true, true)
        font name: 'Monospace', height: 11
      }

      # ── Default buttons (keep these) ─────────────────────────
      button {
        layout_data(:fill, :fill, true, false)
        text 'Create Test File'
        on_widget_selected {
          @fs.write_file('/test.txt', "Hello!\nCreated at: #{Time.now}")
          populate_file_list(file_list_widget)
        }
      }

      button {
        layout_data(:fill, :fill, true, false)
        text 'Clear Chat History'
        on_widget_selected {
          @memory.clear
          message_box { text 'Done'; message 'History cleared.' }.open
        }
      }

      button {
        layout_data(:fill, :fill, true, false)
        text 'Refresh'
        on_widget_selected { populate_file_list(file_list_widget) }
      }

      # ── New custom button ─────────────────────────────────────
      button {
        layout_data(:fill, :fill, true, false)
        text '<Button Label>'
        on_widget_selected {
          # your action here
          message_box { text 'Done'; message 'Action completed.' }.open
        }
      }
    }

    populate_file_list(file_list_widget)
    admin.open
  end
end
```

Then change the launch line to:
```ruby
MyApp.launch!(use_llamafile: true)
```

**Glimmer DSL rules to enforce:**
- `layout_data(:fill, :fill, true, false)` — always use argument form, never block form
- Never call widget methods from a background thread — wrap in `async_exec { }`
- Never use `sash_form` — invisible on macOS

Verify syntax:
```bash
bundle exec ruby -e "require 'zuzu'; load 'app.rb' rescue puts $!.message" 2>&1
```

Done. Tell the user to restart.

---

## Route E — Something else

Read `AGENTS.md` for the relevant section and implement accordingly.
Always verify with a syntax check after making changes:

```bash
bundle exec ruby -e "require 'zuzu'; load 'app.rb' rescue puts $!.message" 2>&1
```
