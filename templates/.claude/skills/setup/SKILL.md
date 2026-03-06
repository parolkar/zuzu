---
name: setup
description: First-time setup for a Zuzu app. Verifies JRuby and Java versions, runs bundle install, checks the model file exists, and does a smoke-test launch. Use when the developer first clones or scaffolds the app, or when the runtime environment seems broken.
---

# Zuzu App Setup

Run each step automatically. Only pause when the user must take an action (e.g. downloading a model file). Fix problems directly — don't tell the user to fix them unless it genuinely requires their input.

## Step 1 — Verify Java 21+

```bash
java -version 2>&1
```

- If missing or < 21: `brew install --cask temurin@21` (macOS) or `sudo apt-get install openjdk-21-jdk` (Linux). Re-check after.
- If correct: continue.

## Step 2 — Verify JRuby 10.0.3.0

```bash
ruby -v
```

- Must show `jruby 10.0.3.0`. If not:
  - Check rbenv: `rbenv versions`
  - If jruby-10.0.3.0 is listed but not active: `rbenv local jruby-10.0.3.0`
  - If not installed: `rbenv install jruby-10.0.3.0 && rbenv local jruby-10.0.3.0`
  - Re-check after.

## Step 3 — Bundle install

```bash
bundle install 2>&1
```

- If fails: read the error. Common fixes:
  - Native extension failure → ensure Java 21 is on PATH, retry
  - Network error → `bundle config mirror.https://rubygems.org https://rubygems.org`, retry
  - Wrong ruby → `rbenv local jruby-10.0.3.0`, retry

## Step 4 — Verify Zuzu loads

```bash
bundle exec ruby -e "require 'zuzu'; puts 'Zuzu ' + Zuzu::VERSION + ' loaded OK'"
```

- If LoadError: re-run `bundle install`, then retry.

## Step 5 — Check model file

Read `app.rb` and find the `c.llamafile_path` value.

Check if the model file exists at that path:

```bash
ls -lh <extracted_model_path>
```

- If missing:
  - AskUserQuestion: "No model file found. Would you like instructions for downloading llava-v1.5-7b-q4.llamafile (~4 GB)?"
  - If yes, tell the user:
    ```bash
    mkdir -p models
    curl -L -o models/llava-v1.5-7b-q4.llamafile \
      https://huggingface.co/Mozilla/llava-v1.5-7b-llamafile/resolve/main/llava-v1.5-7b-q4.llamafile
    chmod +x models/llava-v1.5-7b-q4.llamafile
    ```
  - This requires the user to run it (large download). Tell them to re-run `/setup` after.
- If exists but not executable: `chmod +x <path>` — do this automatically.
- If exists and executable: continue.

## Step 6 — Smoke test (without model)

Test that the Ruby code parses and tools load without launching the GUI:

```bash
bundle exec ruby -e "
require 'zuzu'
load 'app.rb' rescue nil
puts 'Tools registered: ' + Zuzu::ToolRegistry.tools.map(&:name).join(', ')
" 2>&1 | head -20
```

- If it shows tool names: good.
- If Ruby syntax error or LoadError: read the error, fix it in `app.rb`, retry.

## Step 7 — Summary

Tell the user:
- ✅ Java version found
- ✅ JRuby version confirmed
- ✅ Gems installed
- ✅ Zuzu loads
- ✅/⚠️ Model file status
- ✅ Tools registered: (list them)

If model is ready:
> Everything is set. Run `bundle exec zuzu start` to launch the app.

If model is missing:
> Download the model file (see step 5), then run `bundle exec zuzu start`.
