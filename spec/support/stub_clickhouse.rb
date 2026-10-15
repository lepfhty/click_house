# frozen_string_literal: true

# Builds a connection whose requests never leave the process: Faraday's test adapter
# answers every GET and POST with a canned response, which then goes through the real
# middleware stack, Response::Factory and ResultSet type casting.
# Tag examples that use it with :offline so they skip the hooks that talk to a server.
#
# @example
#   connection = stub_clickhouse(body: '{"meta": [], "data": []}')
#   connection.select_all('SELECT 1')
#   clickhouse_requests.last.params #=> { "default_format" => "JSON", ... }
module StubClickHouse
  JSON_HEADERS = { 'Content-Type' => 'application/json; charset=UTF-8' }.freeze

  Request = Struct.new(:method, :path, :params, :headers, :body)

  # @param status [Integer] response status
  # @param headers [Hash] response headers
  # @param body [String] response body
  # @param config [Hash] overrides for a clone of ClickHouse.config
  # @return [ClickHouse::Connection]
  def stub_clickhouse(status: 200, headers: JSON_HEADERS, body: '', **config)
    respond = lambda do |env|
      clickhouse_requests << Request.new(env.method, env.url.path, env.params, env.request_headers.dup, env.request_body)
      [status, headers, body]
    end

    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get(//, &respond)
    stubs.post(//, &respond)

    ClickHouse::Connection.new(
      ClickHouse.config.clone.assign(url: 'http://clickhouse.test:8123', adapter: [:test, stubs], **config)
    )
  end

  # @return [Array<Request>] requests sent by connections from #stub_clickhouse, oldest first
  def clickhouse_requests
    @clickhouse_requests ||= []
  end
end

RSpec.configure do |config|
  config.include StubClickHouse
end
