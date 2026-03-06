# frozen_string_literal: true

require 'json'

module Zuzu
  # Prompt-based agent loop using <zuzu_tool_call> tags.
  # Works with any instruction-following model — no native function-calling required.
  class Agent
    MAX_ITERATIONS = 10

    TOOL_CALL_RE   = /<zuzu_tool_call>(.*?)<\/zuzu_tool_call>/m
    TOOL_RESULT_RE = /<zuzu_tool_result>.*?<\/zuzu_tool_result>/m

    BASE_PROMPT = <<~PROMPT
      You are Zuzu, a helpful desktop AI assistant.

      You have access to a sandboxed virtual filesystem called AgentFS. It is completely
      separate from the host computer's filesystem. All file paths refer to AgentFS only.
      You cannot access or modify any files on the host system.

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

    def initialize(agent_fs:, memory:, llm:)
      @fs     = agent_fs
      @memory = memory
      @llm    = llm
    end

    def process(user_message, &on_tool_call)
      @memory.append(:user, user_message)

      # Only system prompt + current message — no history injected into agent context.
      # Prior non-tool-call responses cause models to skip tool use.
      messages = [
        { 'role' => 'system', 'content' => build_system_prompt },
        { 'role' => 'user',   'content' => user_message }
      ]

      final      = nil
      seen_calls = Hash.new(0)

      MAX_ITERATIONS.times do
        response  = @llm.chat(messages)
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
            $stderr.puts "[zuzu] loop detected for #{tc['name']}, breaking"
            next "<zuzu_tool_result>#{JSON.generate({ name: tc['name'], result: 'Already done. Give your final answer now.' })}</zuzu_tool_result>"
          end

          out = ToolRegistry.execute(tc['name'], tc['args'], @fs)
          $stderr.puts "[zuzu] tool #{tc['name']}(#{tc['args'].inspect}) => #{out.to_s[0, 120]}"
          on_tool_call&.call(tc['name'], tc['args'], out)
          "<zuzu_tool_result>#{JSON.generate({ name: tc['name'], result: out })}</zuzu_tool_result>"
        end.join("\n")

        messages << { 'role' => 'user', 'content' => results }
      end

      final ||= 'Max iterations reached.'
      @memory.append(:assistant, final)
      final
    rescue StandardError => e
      $stderr.puts "[zuzu] Agent error: #{e.message}"
      $stderr.puts e.backtrace.first(10).map { |l| "  #{l}" }.join("\n")
      error_msg = "Error: #{e.message}"
      @memory.append(:assistant, error_msg)
      error_msg
    end

    private

    def build_system_prompt
      tool_lines = ToolRegistry.tools.map do |t|
        args = t.schema[:properties]&.keys&.map(&:to_s)&.join(', ')
        line = "- #{t.name} : #{t.description}"
        line += " Args: #{args}" if args && !args.empty?
        line
      end.join("\n")

      extras = Zuzu.config.system_prompt_extras.to_s.strip

      prompt = BASE_PROMPT.dup
      prompt << "\nAvailable tools:\n#{tool_lines}\n"
      prompt << "\n#{extras}" unless extras.empty?
      prompt.strip
    end

    def extract_tool_calls(content)
      content.scan(TOOL_CALL_RE).filter_map do |match|
        data = JSON.parse(match[0].strip)
        { 'name' => data['name'].to_s, 'args' => data['args'] || {} }
      rescue JSON::ParserError
        nil
      end
    end
  end
end
