# frozen_string_literal: true

# ============================================================================
# Zuzu Standalone — A working JRuby desktop chat app with local LLM
# ============================================================================
# This is the "target app" — a single-file, fully working desktop AI chat
# built on Glimmer DSL for SWT + llamafile + SQLite (JDBC).
#
# Run:  bundle exec ruby app.rb
#
# Dependencies: glimmer-dsl-swt, jdbc-sqlite3, webrick, bigdecimal, logger
# Runtime: JRuby 10.x + JDK 21+
# ============================================================================

require 'glimmer-dsl-swt'
require 'jdbc/sqlite3'
require 'net/http'
require 'openssl'
require 'json'
require 'fileutils'

Jdbc::SQLite3.load_driver

# ── Database ─────────────────────────────────────────────────────
# SQLite via JDBC — stores conversation history and a virtual filesystem.

module Store
  DB_PATH = File.expand_path('.zuzu/zuzu.db', __dir__)
  @mutex  = Mutex.new

  def self.connection
    @connection ||= begin
      FileUtils.mkdir_p(File.dirname(DB_PATH))
      conn = Java::OrgSqlite::JDBC.new.connect("jdbc:sqlite:#{DB_PATH}", java.util.Properties.new)
      stmt = conn.create_statement
      stmt.execute_update("PRAGMA journal_mode=WAL")
      stmt.close
      bootstrap(conn)
      conn
    end
  end

  def self.bootstrap(conn)
    sqls = <<~SQL
      CREATE TABLE IF NOT EXISTS messages (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        role       TEXT NOT NULL,
        content    TEXT NOT NULL,
        created_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS fs_inodes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        type       TEXT NOT NULL CHECK(type IN ('file','dir')),
        content    BLOB,
        size       INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
      CREATE TABLE IF NOT EXISTS fs_dentries (
        id        INTEGER PRIMARY KEY AUTOINCREMENT,
        name      TEXT NOT NULL,
        parent_id INTEGER NOT NULL,
        inode_id  INTEGER NOT NULL,
        UNIQUE(parent_id, name)
      );
      CREATE TABLE IF NOT EXISTS kv_store (
        key        TEXT PRIMARY KEY,
        value      TEXT,
        updated_at INTEGER
      );
    SQL
    sqls.split(';').each do |ddl|
      next if ddl.strip.empty?
      stmt = conn.create_statement
      stmt.execute_update(ddl)
      stmt.close
    end
    # Ensure root inode for virtual FS
    now = (Time.now.to_f * 1000).to_i
    ps = conn.prepare_statement(
      "INSERT OR IGNORE INTO fs_inodes (id, type, content, size, created_at, updated_at) VALUES (1, 'dir', NULL, 0, ?, ?)"
    )
    ps.set_object(1, now)
    ps.set_object(2, now)
    ps.execute_update
    ps.close
  end

  # ── Simple query helpers ──────────────────────────────────────

  def self.execute(sql, params = [])
    @mutex.synchronize do
      ps = connection.prepare_statement(sql)
      params.each_with_index { |v, i| ps.set_object(i + 1, v) }
      ps.execute_update
    ensure
      ps&.close
    end
  end

  def self.query_all(sql, params = [])
    @mutex.synchronize do
      ps = connection.prepare_statement(sql)
      params.each_with_index { |v, i| ps.set_object(i + 1, v) }
      rs   = ps.execute_query
      meta = rs.meta_data
      cols = (1..meta.column_count).map { |c| meta.get_column_name(c) }
      rows = []
      while rs.next
        row = {}
        cols.each { |col| row[col] = rs.get_object(col) }
        rows << row
      end
      rows
    ensure
      rs&.close
      ps&.close
    end
  end

  def self.query_one(sql, params = [])
    query_all(sql, params).first
  end

  def self.last_insert_id
    @mutex.synchronize do
      stmt = connection.create_statement
      rs   = stmt.execute_query("SELECT last_insert_rowid()")
      rs.next ? rs.get_long(1) : nil
    ensure
      rs&.close
      stmt&.close
    end
  end

  def self.close
    @mutex.synchronize do
      @connection&.close
      @connection = nil
    end
  rescue StandardError
    # best-effort
  end
end

# ── Conversation Memory ──────────────────────────────────────────

module Memory
  def self.append(role, content)
    Store.execute(
      "INSERT INTO messages (role, content, created_at) VALUES (?, ?, ?)",
      [role.to_s, content.to_s, (Time.now.to_f * 1000).to_i]
    )
  end

  def self.recent(limit = 20)
    Store.query_all(
      "SELECT role, content FROM messages ORDER BY id DESC LIMIT ?", [limit]
    ).reverse
  end

  def self.clear
    Store.execute("DELETE FROM messages")
  end
end

# ── Virtual Filesystem (AgentFS) ─────────────────────────────────

module AgentFS
  def self.write_file(path, content)
    parts    = split(path)
    filename = parts.pop
    parent   = ensure_parents(parts)
    now      = epoch
    bytes    = content.to_s.to_java_bytes

    dentry = find_dentry(parent, filename)
    if dentry
      Store.execute(
        "UPDATE fs_inodes SET content = ?, size = ?, updated_at = ? WHERE id = ?",
        [bytes, content.to_s.bytesize, now, dentry['inode_id']]
      )
    else
      Store.execute(
        "INSERT INTO fs_inodes (type, content, size, created_at, updated_at) VALUES ('file', ?, ?, ?, ?)",
        [bytes, content.to_s.bytesize, now, now]
      )
      inode_id = Store.last_insert_id
      Store.execute(
        "INSERT INTO fs_dentries (name, parent_id, inode_id) VALUES (?, ?, ?)",
        [filename, parent, inode_id]
      )
    end
    true
  end

  def self.read_file(path)
    inode = resolve(path)
    return nil unless inode
    row = Store.query_one("SELECT content FROM fs_inodes WHERE id = ?", [inode])
    return nil unless row
    blob = row['content']
    blob.is_a?(Java::byte[]) ? String.from_java_bytes(blob) : blob.to_s
  end

  def self.list_dir(path = '/')
    inode = resolve(path)
    return [] unless inode
    Store.query_all("SELECT name FROM fs_dentries WHERE parent_id = ?", [inode]).map { |r| r['name'] }
  end

  def self.stat(path)
    inode_id = resolve(path)
    return nil unless inode_id
    Store.query_one("SELECT id, type, size, created_at, updated_at FROM fs_inodes WHERE id = ?", [inode_id])
  end

  def self.exists?(path)
    !resolve(path).nil?
  end

  # ── KV store ────────────────────────────────────────────────

  def self.kv_set(key, value)
    Store.execute(
      "INSERT OR REPLACE INTO kv_store (key, value, updated_at) VALUES (?, ?, ?)",
      [key, value, epoch]
    )
  end

  def self.kv_get(key)
    row = Store.query_one("SELECT value FROM kv_store WHERE key = ?", [key])
    row && row['value']
  end

  # ── Private helpers ─────────────────────────────────────────

  def self.split(path)
    path.to_s.split('/').reject(&:empty?)
  end

  def self.epoch
    (Time.now.to_f * 1000).to_i
  end

  def self.resolve(path)
    current = 1  # root inode
    split(path).each do |name|
      d = find_dentry(current, name)
      return nil unless d
      current = d['inode_id']
    end
    current
  end

  def self.find_dentry(parent_id, name)
    Store.query_one(
      "SELECT id, inode_id FROM fs_dentries WHERE parent_id = ? AND name = ?",
      [parent_id, name]
    )
  end

  def self.ensure_parents(parts)
    current = 1
    parts.each do |name|
      d = find_dentry(current, name)
      if d
        current = d['inode_id']
      else
        now = epoch
        Store.execute(
          "INSERT INTO fs_inodes (type, content, size, created_at, updated_at) VALUES ('dir', NULL, 0, ?, ?)",
          [now, now]
        )
        inode_id = Store.last_insert_id
        Store.execute(
          "INSERT INTO fs_dentries (name, parent_id, inode_id) VALUES (?, ?, ?)",
          [name, current, inode_id]
        )
        current = inode_id
      end
    end
    current
  end
end

# ── LLM Client ───────────────────────────────────────────────────

module LLM
  HOST = '127.0.0.1'
  PORT = 8080

  def self.alive?
    uri = URI("http://#{HOST}:#{PORT}/v1/models")
    Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
  rescue StandardError
    false
  end

  def self.chat(messages, tools: [])
    body = {
      model:    'LLaMA_CPP',
      messages: messages,
      temperature: 0.1
    }
    body[:tools] = tools unless tools.empty?

    uri = URI("http://#{HOST}:#{PORT}/v1/chat/completions")
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
    req.body = JSON.generate(body)

    res = Net::HTTP.start(uri.host, uri.port, read_timeout: 120) { |http| http.request(req) }
    data = JSON.parse(res.body)
    msg = data.dig('choices', 0, 'message')
    return msg unless msg

    # Strip llamafile EOS tokens
    if msg['content'].is_a?(String)
      msg['content'] = msg['content']
        .gsub(/<\/?s>/, '')
        .gsub(%r{\[/?INST\]}, '')
        .strip
    end
    msg
  end
end

# ── Tools ────────────────────────────────────────────────────────

module Tools
  REGISTRY = {}

  def self.register(name, description, schema, &block)
    REGISTRY[name] = { name: name, desc: description, schema: schema, fn: block }
  end

  def self.openai_schema
    REGISTRY.values.map do |t|
      { type: 'function', function: { name: t[:name], description: t[:desc], parameters: t[:schema] } }
    end
  end

  def self.call(name, args)
    tool = REGISTRY[name]
    return "Error: unknown tool '#{name}'" unless tool
    tool[:fn].call(args).to_s
  rescue StandardError => e
    "Error: #{e.message}"
  end

  # Register built-in tools
  register('read_file', 'Read a file from the sandbox filesystem.',
    { type: 'object', properties: { path: { type: 'string' } }, required: ['path'] }
  ) { |args| AgentFS.read_file(args['path']) || "File not found: #{args['path']}" }

  register('write_file', 'Write content to a file in the sandbox filesystem.',
    { type: 'object', properties: { path: { type: 'string' }, content: { type: 'string' } }, required: %w[path content] }
  ) { |args| AgentFS.write_file(args['path'], args['content']); "Written #{args['content'].bytesize} bytes to #{args['path']}" }

  register('list_directory', 'List files in a directory.',
    { type: 'object', properties: { path: { type: 'string' } }, required: [] }
  ) { |args| entries = AgentFS.list_dir(args['path'] || '/'); entries.empty? ? '(empty)' : entries.join("\n") }

  register('run_command', 'Run a command against the AgentFS sandbox (NOT the host filesystem).',
    { type: 'object', properties: { command: { type: 'string' } }, required: ['command'] }
  ) do |args|
    cmd   = args['command'].to_s.strip
    parts = cmd.split(/\s+/)
    base  = parts[0]

    case base
    when 'ls'
      path    = parts[1] || '/'
      stat    = AgentFS.stat(path)
      if stat && stat['type'] == 'file'
        "#{path} (file, #{stat['size']} bytes)"
      else
        entries = AgentFS.list_dir(path)
        entries.empty? ? '(empty directory)' : entries.join("\n")
      end
    when 'cat'
      path = parts[1]
      path ? (AgentFS.read_file(path) || "File not found in AgentFS: #{path}") : 'Usage: cat <path>'
    when 'pwd'
      '/'
    when 'echo'
      parts[1..].join(' ')
    else
      "Error: '#{base}' is not available in the AgentFS sandbox. Supported: ls, cat, pwd, echo."
    end
  end

  register('http_get', 'Fetch a URL via HTTP GET.',
    { type: 'object', properties: { url: { type: 'string' } }, required: ['url'] }
  ) do |args|
    uri = URI.parse(args['url'].to_s)
    raise ArgumentError, 'Only http/https supported' unless %w[http https].include?(uri.scheme)
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                          open_timeout: 10, read_timeout: 15,
                          verify_mode: OpenSSL::SSL::VERIFY_NONE) { |h| h.get(uri.request_uri) }
    res.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace).slice(0, 8192)
  end
end

# ── Agent Loop ───────────────────────────────────────────────────

module Agent
  SYSTEM_PROMPT = <<~PROMPT.strip
    You are Zuzu, a helpful desktop AI assistant.

    You have access to a sandboxed virtual filesystem called AgentFS. It is completely
    separate from the host computer's filesystem. All file paths refer to AgentFS only.
    You cannot access or modify any files on the host system.

    Available tools — use the tag format shown below:

    - write_file     : Write text to an AgentFS file. Args: path (string), content (string)
    - read_file      : Read an AgentFS file. Args: path (string)
    - list_directory : List an AgentFS directory. Args: path (string, default "/")
    - run_command    : Run a sandboxed command against AgentFS. Args: command (string)
                       Supported: ls [path], cat <path>, pwd, echo <text>
    - http_get       : Fetch a public URL from the internet. Args: url (string)

    To call a tool, output exactly this on its own line:
    <zuzu_tool_call>{"name":"TOOL_NAME","args":{"key":"value"}}</zuzu_tool_call>

    Rules:
    - One tool call per turn. Wait for the <zuzu_tool_result> before calling another.
    - After the task is complete, respond in plain text only (no XML tags of any kind).
    - Do NOT verify or re-read files after writing them unless explicitly asked.
    - Do NOT repeat a tool call you have already made.
    - Never reference the host filesystem, shell environment, or paths like /home/user.
    - Be concise and accurate.
  PROMPT

  TOOL_CALL_RE  = /<zuzu_tool_call>(.*?)<\/zuzu_tool_call>/m
  TOOL_RESULT_RE = /<zuzu_tool_result>.*?<\/zuzu_tool_result>/m
  MAX_TURNS = 10

  def self.process(user_message, &on_tool_call)
    Memory.append(:user, user_message)

    # Only send system prompt + current message to the agent.
    # Conversation history is shown in the UI but not injected into the LLM context,
    # because prior non-tool-call responses cause the model to skip tool use.
    messages = [
      { 'role' => 'system', 'content' => SYSTEM_PROMPT },
      { 'role' => 'user',   'content' => user_message }
    ]

    final = nil
    seen_calls = Hash.new(0)

    MAX_TURNS.times do
      response  = LLM.chat(messages)
      content   = response['content'].to_s.strip

      tool_calls = extract_tool_calls(content)

      if tool_calls.empty?
        final = content.gsub(TOOL_RESULT_RE, '').strip
        break
      end

      messages << { 'role' => 'assistant', 'content' => content }

      results = tool_calls.map do |tc|
        sig = "#{tc['name']}:#{tc['args'].to_json}"
        seen_calls[sig] += 1
        if seen_calls[sig] > 2
          $stderr.puts "[zuzu] loop detected for #{tc['name']}, aborting"
          next "<zuzu_tool_result>#{JSON.generate({ name: tc['name'], result: 'Already done. Stop repeating this call and give your final answer.' })}</zuzu_tool_result>"
        end

        out = Tools.call(tc['name'], tc['args'])
        $stderr.puts "[zuzu] tool #{tc['name']}(#{tc['args'].inspect}) => #{out.to_s[0, 120]}"
        on_tool_call&.call(tc['name'], tc['args'], out)
        "<zuzu_tool_result>#{JSON.generate({ name: tc['name'], result: out })}</zuzu_tool_result>"
      end.join("\n")

      messages << { 'role' => 'user', 'content' => results }
    end

    final ||= 'Max iterations reached.'
    Memory.append(:assistant, final)
    final
  rescue StandardError => e
    $stderr.puts "[zuzu] Agent error: #{e.message}"
    $stderr.puts e.backtrace.first(10).map { |l| "  #{l}" }.join("\n")
    error_msg = "Error: #{e.message}"
    Memory.append(:assistant, error_msg)
    error_msg
  end

  def self.extract_tool_calls(content)
    content.scan(TOOL_CALL_RE).filter_map do |match|
      data = JSON.parse(match[0].strip)
      { 'name' => data['name'].to_s, 'args' => data['args'] || {} }
    rescue JSON::ParserError
      nil
    end
  end
end

# ── Llamafile Manager ────────────────────────────────────────────

module Llamafile
  STARTUP_TIMEOUT = 60  # seconds — models can take a while to load
  @pid = nil

  def self.start!(path, port: 8080)
    return if @pid
    raise "llamafile not found: #{path}" unless File.exist?(path.to_s)

    log_file = File.expand_path('llama.log', File.dirname(path))
    @pid = Process.spawn(
      path, '--server', '--port', port.to_s, '--nobrowser',
      out: log_file, err: log_file
    )
    Process.detach(@pid)

    deadline = Time.now + STARTUP_TIMEOUT
    until LLM.alive?
      if Time.now > deadline
        stop!
        raise "llamafile failed to start within #{STARTUP_TIMEOUT}s (check #{log_file})"
      end
      sleep 1
    end
  end

  def self.stop!
    return unless @pid
    Process.kill('TERM', @pid) rescue nil
    sleep 0.5
    Process.kill('KILL', @pid) rescue nil
    @pid = nil
  end

  def self.running?
    @pid && (Process.kill(0, @pid) rescue false)
  end
end

# ── GUI ──────────────────────────────────────────────────────────
# The actual desktop app. This is what the user sees and interacts with.
# Built following official Glimmer DSL for SWT patterns from:
#   - hello_scrolled_composite.rb  (scrolled content)
#   - hello_sash_form.rb           (split pane)
#   - hello_custom_shell.rb        (CustomShell / Application)

class ZuzuApp
  include Glimmer::UI::Application

  APP_NAME      = 'My Assistant'
  WINDOW_WIDTH  = 860
  WINDOW_HEIGHT = 620

  USER_BG      = rgb(66, 133, 244)
  ASSISTANT_BG = rgb(225, 235, 255)

  attr_accessor :user_input

  before_body do
    @user_input = ''
  end

  body {
    shell {
      grid_layout 1, false
      text APP_NAME
      size WINDOW_WIDTH, WINDOW_HEIGHT

      # ── Chat display ───────────────────────────────────────
      scrolled_composite(:v_scroll) {
        layout_data(:fill, :fill, true, true)

        @chat_display = text(:multi, :read_only, :wrap) {
          background :white
          font name: 'Monospace', height: 13
        }
      }

      # ── Input row ──────────────────────────────────────────
      composite {
        layout_data(:fill, :fill, true, false)
        grid_layout 3, false

        @input_text = text(:border) {
          layout_data(:fill, :fill, true, false)
          text <=> [self, :user_input]
          on_key_pressed do |e|
            send_message if e.character == 13
          end
        }

        button {
          text 'Send'
          on_widget_selected { send_message }
        }

        button {
          text 'Admin Panel'
          on_widget_selected { open_admin_panel }
        }
      }
    }
  }

  def send_message
    input = user_input.to_s.strip
    return if input.empty?

    self.user_input = ''
    add_bubble(:user, input)

    Thread.new do
      begin
        response = Agent.process(input) do |tool_name, args, result|
          async_exec { add_bubble(:tool, "#{tool_name}(#{args.map { |k,v| "#{k}: #{v.to_s[0,40]}" }.join(', ')}) → #{result.to_s[0, 80]}") }
        end
        async_exec { add_bubble(:assistant, response) }
      rescue => e
        async_exec { add_bubble(:assistant, "Error: #{e.message}") }
      end
    end
  end

  private

  def add_bubble(role, msg)
    prefix = case role
             when :user      then "You: "
             when :assistant then "Assistant: "
             when :tool      then "  [tool] "
             end
    current = @chat_display.swt_widget.get_text
    separator = current.empty? ? '' : "\n"
    separator = "\n\n" if role != :tool
    @chat_display.swt_widget.set_text(current + separator + prefix + msg.to_s)
    @chat_display.swt_widget.set_top_index(@chat_display.swt_widget.get_line_count)
  end

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

      button {
        layout_data(:fill, :fill, true, false)
        text 'Create Test File'
        on_widget_selected {
          AgentFS.write_file('/test.txt', "Hello from AgentFS!\nCreated at: #{Time.now}")
          populate_file_list(file_list_widget)
        }
      }

      button {
        layout_data(:fill, :fill, true, false)
        text 'Clear Chat History'
        on_widget_selected {
          Memory.clear
          message_box {
            text 'Done'
            message 'Conversation history cleared.'
          }.open
        }
      }

      button {
        layout_data(:fill, :fill, true, false)
        text 'Refresh'
        on_widget_selected { populate_file_list(file_list_widget) }
      }
    }

    populate_file_list(file_list_widget)
    admin.open
  end

  def populate_file_list(file_list)
    entries = walk_fs('/')
    items = entries.empty? ? ['(empty)'] : entries
    file_list.swt_widget.set_items(items.to_java(:string))
  rescue => e
    file_list.swt_widget.set_items(["Error: #{e.message}"].to_java(:string))
  end

  def walk_fs(path, indent = 0)
    AgentFS.list_dir(path).flat_map do |name|
      child = path == '/' ? "/#{name}" : "#{path}/#{name}"
      stat  = AgentFS.stat(child)
      if stat && stat['type'] == 'dir'
        ["#{'  ' * indent}+ #{name}/"] + walk_fs(child, indent + 1)
      else
        ["#{'  ' * indent}  #{name}"]
      end
    end
  end
end

# ── Launch ───────────────────────────────────────────────────────
# Configure your llamafile path here. Comment out the Llamafile.start!
# line if you want to start the model manually.

LLAMAFILE_PATH = File.expand_path('models/llava-v1.5-7b-q4.llamafile', __dir__)

begin
  if File.exist?(LLAMAFILE_PATH)
    Llamafile.start!(LLAMAFILE_PATH, port: 8080)
  else
    $stderr.puts "[zuzu] No llamafile found at #{LLAMAFILE_PATH}"
    $stderr.puts "[zuzu] Start one manually or update LLAMAFILE_PATH in app.rb"
    $stderr.puts "[zuzu] The chat UI will still open — LLM calls will fail until a model is running."
  end

  ZuzuApp.launch
ensure
  Llamafile.stop!
  Store.close
end
