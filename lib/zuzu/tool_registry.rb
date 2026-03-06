# frozen_string_literal: true

require 'json'

module Zuzu
  # Global registry of callable tools for the agent loop.
  module ToolRegistry
    Tool = Struct.new(:name, :description, :schema, :block, keyword_init: true)

    @tools = {}

    class << self
      def register(name, description, schema, &block)
        @tools[name.to_s] = Tool.new(
          name: name.to_s, description: description,
          schema: schema, block: block
        )
      end

      def tools  = @tools.values
      def find(name) = @tools[name.to_s]

      def to_openai_schema
        tools.map do |t|
          { type: 'function', function: { name: t.name, description: t.description, parameters: t.schema } }
        end
      end

      def execute(name, args, agent_fs)
        tool = find(name) or return "Error: unknown tool '#{name}'"
        started = Time.now.to_f
        output = begin
          tool.block.call(args, agent_fs)
        rescue StandardError => e
          "Error: #{e.message}"
        end
        finished = Time.now.to_f
        agent_fs.record_tool_call(name, JSON.generate(args), output.to_s, started, finished)
        output.to_s
      end
    end
  end
end
