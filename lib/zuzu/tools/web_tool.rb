# frozen_string_literal: true

require 'net/http'
require 'uri'

Zuzu::ToolRegistry.register(
  'http_get', 'Fetch a URL via HTTP GET (truncated to 8 KB).',
  { type: 'object', properties: { url: { type: 'string', description: 'URL to fetch' } }, required: ['url'] }
) do |args, _fs|
  uri = URI.parse(args['url'].to_s)
  raise ArgumentError, 'Only http/https supported' unless %w[http https].include?(uri.scheme)
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                        open_timeout: 10, read_timeout: 15) { |h| h.get(uri.request_uri, 'User-Agent' => 'Zuzu/1.0') }
  res.body.to_s.encode('UTF-8', invalid: :replace, undef: :replace).slice(0, 8192)
end
