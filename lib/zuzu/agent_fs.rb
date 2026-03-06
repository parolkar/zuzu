# frozen_string_literal: true

module Zuzu
  # Virtual filesystem backed by SQLite via JDBC.
  # Provides sandboxed file I/O and a key-value store for the agent.
  class AgentFS
    SCHEMA = <<~SQL
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
      CREATE TABLE IF NOT EXISTS tool_calls (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        tool_name   TEXT,
        input       TEXT,
        output      TEXT,
        started_at  REAL,
        finished_at REAL
      );
    SQL

    attr_reader :store

    def initialize(store = nil)
      @store = store || Store.new
      bootstrap
    end

    # ── File operations ──────────────────────────────────────────

    def write_file(path, content)
      parts    = split(path)
      filename = parts.pop
      parent   = ensure_parents(parts)
      now      = epoch
      bytes    = content.to_s.to_java_bytes

      dentry = find_dentry(parent, filename)
      if dentry
        @store.execute(
          "UPDATE fs_inodes SET content = ?, size = ?, updated_at = ? WHERE id = ?",
          [bytes, content.to_s.bytesize, now, dentry['inode_id']]
        )
      else
        @store.execute(
          "INSERT INTO fs_inodes (type, content, size, created_at, updated_at) VALUES ('file', ?, ?, ?, ?)",
          [bytes, content.to_s.bytesize, now, now]
        )
        inode_id = @store.last_insert_id
        @store.execute(
          "INSERT INTO fs_dentries (name, parent_id, inode_id) VALUES (?, ?, ?)",
          [filename, parent, inode_id]
        )
      end
      true
    end

    def read_file(path)
      inode = resolve(path)
      return nil unless inode
      row = @store.query_one("SELECT content FROM fs_inodes WHERE id = ?", [inode])
      return nil unless row
      blob = row['content']
      blob.is_a?(Java::byte[]) ? String.from_java_bytes(blob) : blob.to_s
    end

    def list_dir(path = '/')
      inode = resolve(path)
      return [] unless inode
      @store.query_all("SELECT name FROM fs_dentries WHERE parent_id = ?", [inode]).map { |r| r['name'] }
    end

    def mkdir(path)
      parts   = split(path)
      dirname = parts.pop
      parent  = ensure_parents(parts)
      return false if find_dentry(parent, dirname)

      now = epoch
      @store.execute(
        "INSERT INTO fs_inodes (type, content, size, created_at, updated_at) VALUES ('dir', NULL, 0, ?, ?)",
        [now, now]
      )
      inode_id = @store.last_insert_id
      @store.execute(
        "INSERT INTO fs_dentries (name, parent_id, inode_id) VALUES (?, ?, ?)",
        [dirname, parent, inode_id]
      )
      true
    end

    def delete(path)
      parts = split(path)
      name  = parts.pop
      parent = resolve_segments(parts)
      return false unless parent
      dentry = find_dentry(parent, name)
      return false unless dentry
      @store.execute("DELETE FROM fs_dentries WHERE id = ?", [dentry['id']])
      @store.execute("DELETE FROM fs_inodes WHERE id = ?",   [dentry['inode_id']])
      true
    end

    def exists?(path) = !resolve(path).nil?

    def stat(path)
      inode_id = resolve(path)
      return nil unless inode_id
      @store.query_one(
        "SELECT id, type, size, created_at, updated_at FROM fs_inodes WHERE id = ?", [inode_id]
      )
    end

    # ── Key-value store ──────────────────────────────────────────

    def kv_set(key, value)
      @store.execute(
        "INSERT OR REPLACE INTO kv_store (key, value, updated_at) VALUES (?, ?, ?)",
        [key, value, epoch]
      )
    end

    def kv_get(key)
      row = @store.query_one("SELECT value FROM kv_store WHERE key = ?", [key])
      row && row['value']
    end

    def kv_delete(key)
      @store.execute("DELETE FROM kv_store WHERE key = ?", [key])
    end

    def kv_list(prefix = '')
      @store.query_all("SELECT key, value FROM kv_store WHERE key LIKE ?", ["#{prefix}%"])
    end

    # ── Tool-call audit log ──────────────────────────────────────

    def record_tool_call(name, input, output, started_at, finished_at)
      @store.execute(
        "INSERT INTO tool_calls (tool_name, input, output, started_at, finished_at) VALUES (?, ?, ?, ?, ?)",
        [name, input.to_s, output.to_s, started_at, finished_at]
      )
    end

    private

    def split(path) = path.to_s.split('/').reject(&:empty?)
    def epoch       = (Time.now.to_f * 1000).to_i

    def resolve(path)
      resolve_segments(split(path))
    end

    def resolve_segments(parts)
      current = 1  # root inode
      parts.each do |name|
        d = find_dentry(current, name)
        return nil unless d
        current = d['inode_id']
      end
      current
    end

    def find_dentry(parent_id, name)
      @store.query_one(
        "SELECT id, inode_id FROM fs_dentries WHERE parent_id = ? AND name = ?",
        [parent_id, name]
      )
    end

    def ensure_parents(parts)
      current = 1
      parts.each do |name|
        d = find_dentry(current, name)
        if d
          current = d['inode_id']
        else
          now = epoch
          @store.execute(
            "INSERT INTO fs_inodes (type, content, size, created_at, updated_at) VALUES ('dir', NULL, 0, ?, ?)",
            [now, now]
          )
          inode_id = @store.last_insert_id
          @store.execute(
            "INSERT INTO fs_dentries (name, parent_id, inode_id) VALUES (?, ?, ?)",
            [name, current, inode_id]
          )
          current = inode_id
        end
      end
      current
    end

    def bootstrap
      SCHEMA.split(';').each do |ddl|
        next if ddl.strip.empty?
        stmt = @store.connection.create_statement
        stmt.execute_update(ddl)
        stmt.close
      end
      now = epoch
      @store.execute(
        "INSERT OR IGNORE INTO fs_inodes (id, type, content, size, created_at, updated_at) VALUES (1, 'dir', NULL, 0, ?, ?)",
        [now, now]
      )
    end
  end
end
