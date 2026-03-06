# frozen_string_literal: true

require 'webrick'
require 'json'
require 'net/http'

module Zuzu
  module Channels
    # WhatsApp Cloud API webhook receiver.
    class WhatsApp < Base
      API_BASE = 'https://graph.facebook.com/v19.0'

      def start
        port  = Integer(ENV.fetch('WHATSAPP_PORT', 9292))
        @server = WEBrick::HTTPServer.new(
          Port: port, Logger: WEBrick::Log.new(nil, 0), AccessLog: []
        )
        @server.mount_proc('/webhook') { |req, res| dispatch(req, res) }
        @running = true
        @thread  = Thread.new { @server.start }
      end

      def stop
        @server&.shutdown
        @thread&.join
        @running = false
      end

      private

      def dispatch(req, res)
        if req.request_method == 'GET'
          res.body = req.query['hub.challenge'].to_s
        elsif req.request_method == 'POST'
          payload = JSON.parse(req.body)
          entry   = payload.dig('entry', 0, 'changes', 0, 'value')
          msg     = entry&.dig('messages', 0)
          if msg&.dig('type') == 'text'
            text  = msg.dig('text', 'body')
            to    = msg['from']
            reply = handle(text)
            send_reply(to, reply)
          end
          res.body = 'OK'
        end
        res.status = 200
      end

      def send_reply(to, text)
        token    = ENV['WHATSAPP_TOKEN']
        phone_id = ENV['WHATSAPP_PHONE_ID']
        uri  = URI("#{API_BASE}/#{phone_id}/messages")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        req  = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json',
                                        'Authorization' => "Bearer #{token}")
        req.body = { messaging_product: 'whatsapp', to: to,
                     type: 'text', text: { body: text } }.to_json
        http.request(req)
      end
    end
  end
end
