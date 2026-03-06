# frozen_string_literal: true

require 'json'

module Zuzu
  # ReAct-style agent loop.
  # Sends user messages to the LLM with tool definitions,
  # executes tool calls, feeds results back, repeats until done.
  class Agent
    MAX_ITERATIONS = 10

    SYSTEM_PROMPT = <<~PROMPT.strip
      You are Zuzu, a helpful desktop AI assistant. You have access to tools
      that let you read and write files in a sandboxed filesystem, run safe
      shell commands, and fetch web pages. Use them when they help you answer
      the user's question. Be concise and accurate.
    PROMPT

    def initialize(agent_fs:, memory:, llm:)
      @fs     = agent_fs
      @memory = memory
      @llm    = llm
    end

    def process(user_message)
      @memory.append(:user, user_message)

      messages = [{ 'role' => 'system', 'content' => SYSTEM_PROMPT }]
      messages.concat(@memory.context_for_llm)

      tools  = ToolRegistry.to_openai_schema
      final  = nil

      MAX_ITERATIONS.times do
        response = @llm.chat_with_tools(messages, tools)
        calls    = response['tool_calls']

        if calls.nil? || calls.empty?
          final = response['content'].to_s
          break
        end

        messages << response
        calls.each do |tc|
          fn   = tc.dig('function', 'name')
          args = JSON.parse(tc.dig('function', 'arguments') || '{}')
          out  = ToolRegistry.execute(fn, args, @fs)
          messages << { 'role' => 'tool', 'tool_call_id' => tc['id'], 'name' => fn, 'content' => out }
        end
      end

      final ||= 'Max iterations reached without a final response.'
      @memory.append(:assistant, final)
      final
    rescue StandardError => e
      $stderr.puts "[zuzu] Agent error: #{e.message}"
      $stderr.puts e.backtrace.first(10).map { |l| "  #{l}" }.join("\n")
      error_msg = "Error: #{e.message}"
      @memory.append(:assistant, error_msg)
      error_msg
    end
  end
end
