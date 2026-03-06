# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'json'
require 'uri'

module Zuzu
  # HTTP client for llamafile's OpenAI-compatible API.
  class LlmClient
    def initialize(host: '127.0.0.1', port: Zuzu.config.port)
      @host = host
      @port = port
    end

    def chat(messages, temperature: 0.1)
      body = {
        model:       Zuzu.config.model,
        messages:    messages,
        temperature: temperature
      }
      data = post_json('/v1/chat/completions', body)
      msg  = data.dig('choices', 0, 'message')
      strip_eos(msg)
    end

    def alive?
      uri = URI("http://#{@host}:#{@port}/v1/models")
      Net::HTTP.get_response(uri).is_a?(Net::HTTPSuccess)
    rescue StandardError
      false
    end

    def stream(messages, &block)
      body = { model: Zuzu.config.model, messages: messages, stream: true }
      uri  = URI("http://#{@host}:#{@port}/v1/chat/completions")
      req  = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = JSON.generate(body)

      Net::HTTP.start(uri.host, uri.port) do |http|
        http.request(req) do |response|
          response.read_body do |chunk|
            chunk.each_line do |line|
              content = parse_sse(line)
              block.call(content) if content
            end
          end
        end
      end
    end

    private

    def post_json(path, body)
      uri = URI("http://#{@host}:#{@port}#{path}")
      req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
      req.body = JSON.generate(body)
      res = Net::HTTP.start(uri.host, uri.port, read_timeout: 120,
                            use_ssl: false) { |http| http.request(req) }
      JSON.parse(res.body)
    end

    def strip_eos(msg)
      return msg unless msg.is_a?(Hash) && msg['content'].is_a?(String)
      msg['content'] = msg['content']
        .gsub(/<\/?s>/, '')
        .gsub(%r{\[/?INST\]}, '')
        .strip
      msg
    end

    def parse_sse(line)
      line = line.strip
      return nil if line.empty? || line == 'data: [DONE]'
      return nil unless line.start_with?('data: ')
      json = JSON.parse(line.sub('data: ', ''))
      json.dig('choices', 0, 'delta', 'content')
    rescue JSON::ParserError
      nil
    end
  end
end
