# frozen_string_literal: true

# Runs the benchmark suites and appends the results to benchmark/results.csv.
# See benchmark/README.md for usage.

require 'bundler/setup'
require 'optparse'
$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'click_house'
require_relative 'support/environment'
require_relative 'support/fixtures'
require_relative 'support/measure'
require_relative 'support/scenarios'
require_relative 'support/recorder'

options = {
  suite: 'all',
  parser: 'json',
  rows: 100_000,
  iterations: 5,
  warmup: 1,
  port: ENV.fetch('CLICKHOUSE_PORT', '8123'),
  database: 'click_house_bench',
  output: File.expand_path('results.csv', __dir__),
  record: true,
  note: nil,
  only: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: ruby benchmark/run.rb [options]'
  opts.on('--suite SUITE', %w[all offline e2e], 'all (default), offline or e2e') { |v| options[:suite] = v }
  opts.on('--parser PARSER', %w[json oj], 'json (default) or oj') { |v| options[:parser] = v }
  opts.on('--rows N', Integer, 'rows per scenario (default 100000)') { |v| options[:rows] = v }
  opts.on('--iterations N', Integer, 'timed iterations (default 5)') { |v| options[:iterations] = v }
  opts.on('--warmup N', Integer, 'untimed warmup iterations (default 1)') { |v| options[:warmup] = v }
  opts.on('--port PORT', 'ClickHouse HTTP port (default $CLICKHOUSE_PORT or 8123)') { |v| options[:port] = v }
  opts.on('--only REGEX', 'run scenarios whose name matches REGEX') { |v| options[:only] = Regexp.new(v) }
  opts.on('--note TEXT', 'free-text label stored with every row') { |v| options[:note] = v }
  opts.on('--output PATH', 'CSV file to append to') { |v| options[:output] = v }
  opts.on('--no-record', 'print results without writing the CSV') { options[:record] = false }
end.parse!

config = ClickHouse::Config.new(url: "http://localhost:#{options[:port]}", database: options[:database])
if options[:parser] == 'oj'
  config.json_parser = ClickHouse::Middleware::ParseJsonOj
  config.json_serializer = ClickHouse::Serializer::JsonOjSerializer
end

scenarios = []
scenarios.concat(Bench::Scenarios.offline(config, options[:rows])) if %w[all offline].include?(options[:suite])

clickhouse_version = nil
if %w[all e2e].include?(options[:suite])
  connection = ClickHouse::Connection.new(config)
  begin
    clickhouse_version = connection.execute('SELECT version() FORMAT CSV', database: nil).body.dig(0, 0)
  rescue ClickHouse::NetworkException => e
    abort "ClickHouse is not reachable on port #{options[:port]} (#{e.message}). Use --suite offline to skip it."
  end
  Bench::Scenarios.prepare_server(connection, options[:database], options[:rows])
  scenarios.concat(Bench::Scenarios.end_to_end(connection, options[:rows]))
end

scenarios.select! { |scenario| options[:only].match?(scenario.name) } if options[:only]
abort 'No scenarios selected.' if scenarios.empty?

environment = Bench::Environment.capture(config: config, parser: options[:parser], note: options[:note])
puts "run #{environment[:run_id]}#{' (uncommitted changes)' if environment[:git_dirty]}: " \
     "ruby #{environment[:ruby_version]}#{' +YJIT' if environment[:yjit]}, " \
     "faraday #{environment[:faraday_version]}, parser #{options[:parser]}, " \
     "clickhouse #{clickhouse_version || '-'}"

measure = Bench::Measure.new(iterations: options[:iterations], warmup: options[:warmup])
results = scenarios.map do |scenario|
  measure.call(scenario).tap do |result|
    puts format(
      '  %-8<suite>s %-28<scenario>s %10<wall>.1f ms  %10<cpu>.1f ms cpu  %12<allocs>d allocs',
      suite: result.suite, scenario: result.scenario, wall: result.wall_median_ms,
      cpu: result.cpu_median_ms, allocs: result.allocations
    )
  end
end

if options[:record]
  Bench::Recorder.new(options[:output]).append(environment, clickhouse_version, results)
  puts "appended #{results.size} rows to #{options[:output]}"
end
