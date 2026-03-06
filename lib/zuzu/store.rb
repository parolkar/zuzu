# frozen_string_literal: true

require 'jdbc/sqlite3'
require 'fileutils'
Jdbc::SQLite3.load_driver

module Zuzu
  # SQLite query layer used by AgentFS and Memory.
  # One shared JDBC connection per db_path, guarded by a Mutex.
  class Store
    attr_reader :db_path

    def initialize(db_path = Zuzu.config.db_path)
      @db_path = db_path
      @mutex   = Mutex.new
    end

    def connection
      @connection ||= begin
        FileUtils.mkdir_p(File.dirname(@db_path))
        conn = Java::OrgSqlite::JDBC.new.connect(
          "jdbc:sqlite:#{@db_path}", java.util.Properties.new
        )
        # Enable WAL for better concurrent read performance
        stmt = conn.create_statement
        stmt.execute_update("PRAGMA journal_mode=WAL")
        stmt.close
        conn
      end
    end

    def execute(sql, params = [])
      @mutex.synchronize do
        ps = connection.prepare_statement(sql)
        params.each_with_index { |v, i| ps.set_object(i + 1, v) }
        ps.execute_update
      ensure
        ps&.close
      end
    end

    def query_all(sql, params = [])
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

    def query_one(sql, params = [])
      query_all(sql, params).first
    end

    def last_insert_id
      @mutex.synchronize do
        stmt = connection.create_statement
        rs   = stmt.execute_query("SELECT last_insert_rowid()")
        rs.next ? rs.get_long(1) : nil
      ensure
        rs&.close
        stmt&.close
      end
    end

    def close
      @mutex.synchronize do
        @connection&.close
        @connection = nil
      end
    rescue StandardError
      # Best-effort close — don't raise during shutdown
    end
  end
end
