# frozen_string_literal: true

require 'json'

module Zuzu
  # Conversation memory backed by the messages table.
  class Memory
    def initialize(store = nil)
      @store = store || Store.new
      bootstrap
    end

    def append(role, content)
      @store.execute(
        "INSERT INTO messages (role, content, created_at) VALUES (?, ?, ?)",
        [role.to_s, content.to_s, (Time.now.to_f * 1000).to_i]
      )
    end

    def recent(limit = 20)
      @store.query_all(
        "SELECT role, content FROM messages ORDER BY id DESC LIMIT ?", [limit]
      ).reverse
    end

    def clear
      @store.execute("DELETE FROM messages")
    end

    def context_for_llm(limit = 20)
      recent(limit).map { |m| { 'role' => m['role'], 'content' => m['content'] } }
    end

    private

    def bootstrap
      @store.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS messages (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          role       TEXT NOT NULL,
          content    TEXT NOT NULL,
          created_at INTEGER NOT NULL
        )
      SQL
    end
  end
end
