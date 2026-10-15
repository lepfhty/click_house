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
  # @param config [Hash] overrides for the copy of ClickHouse.config (see #stub_config)
  # @return [ClickHouse::Connection]
  def stub_clickhouse(status: 200, headers: JSON_HEADERS, body: '', **config)
    respond = lambda do |env|
      clickhouse_requests << Request.new(env.method, env.url.path, env.params, env.request_headers.dup, env.request_body)
      [status, headers, body]
    end

    stubs = Faraday::Adapter::Test::Stubs.new
    stubs.get(//, &respond)
    stubs.post(//, &respond)

    ClickHouse::Connection.new(stub_config(adapter: [:test, stubs], **config))
  end

  # A copy of ClickHouse.config that shares no mutable state with it, so specs can't leak
  # changes into the global config.
  # @return [ClickHouse::Config]
  def stub_config(**overrides)
    global = ClickHouse.config
    global.clone.assign(
      url: 'http://clickhouse.test:8123',
      headers: global.headers.dup,
      global_params: global.global_params.dup,
      oj_load_options: global.oj_load_options.dup,
      oj_dump_options: global.oj_dump_options.dup,
      json_load_options: global.json_load_options.dup,
      json_serializer: global.json_serializer.class,
      **overrides
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
