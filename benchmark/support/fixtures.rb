# frozen_string_literal: true

module Bench
  # Deterministic synthetic data. Select fixtures follow ClickHouse's JSON output
  # conventions (e.g. UInt64 quoted as strings); insert fixtures use plain JSON values.
  module Fixtures
    BASE_TIME = Time.utc(2024, 1, 1)
    DATETIME = '%Y-%m-%d %H:%M:%S'

    # Single-column types cast in the offline suite, with a JSON value generator each
    CAST_TYPES = {
      'UInt64' => ->(i) { (i * 7919).to_s },
      'Int32' => ->(i) { i - 50_000 },
      'Float64' => ->(i) { i * 1.25 + 0.5 },
      'Decimal(18, 4)' => ->(i) { i + 0.1234 },
      'Bool' => ->(i) { i.even? },
      'String' => ->(i) { "name-#{i}" },
      'LowCardinality(String)' => ->(i) { "country-#{i % 50}" },
      'Nullable(String)' => ->(i) { i % 10 == 0 ? nil : "value-#{i}" },
      'UUID' => ->(i) { format('00000000-0000-4000-8000-%012x', i) },
      'Date' => ->(i) { (BASE_TIME + (i % 3650) * 86_400).strftime('%Y-%m-%d') },
      'DateTime' => ->(i) { (BASE_TIME + i).strftime(DATETIME) },
      "DateTime('UTC')" => ->(i) { (BASE_TIME + i).strftime(DATETIME) },
      "DateTime64(3, 'UTC')" => ->(i) { (BASE_TIME + i).strftime(DATETIME) + format('.%03d', i % 1000) },
      'IPv4' => ->(i) { "10.#{(i >> 16) & 255}.#{(i >> 8) & 255}.#{i & 255}" },
      'Array(String)' => ->(i) { ["tag-#{i % 7}", "tag-#{i % 11}"] },
      'Map(String, UInt64)' => ->(i) { { 'clicks' => i.to_s, 'views' => (i * 3).to_s } }
    }.freeze

    # Table used by the end-to-end suite and the offline serialization scenarios
    MIXED_COLUMNS = {
      'id' => 'UInt64',
      'ts' => "DateTime('UTC')",
      'd' => 'Date',
      'name' => 'String',
      'country' => 'LowCardinality(String)',
      'note' => 'Nullable(String)',
      'value' => 'Float64',
      'amount' => 'Decimal(18, 4)',
      'tags' => 'Array(String)',
      'attrs' => 'Map(String, UInt64)'
    }.freeze

    module_function

    # @return [String] a ClickHouse-style FORMAT JSON response body
    def select_body(columns, rows)
      meta = columns.map { |name, type| { 'name' => name, 'type' => type } }
      data = Array.new(rows) do |i|
        columns.each_with_object({}) { |(name, type), row| row[name] = CAST_TYPES.fetch(type).call(i) }
      end

      JSON.generate('meta' => meta, 'data' => data, 'rows' => rows, 'statistics' => { 'elapsed' => 0.01 })
    end

    # @return [Array<Hash>] rows for JSONEachRow inserts into the mixed table
    def insert_rows(rows)
      Array.new(rows) do |i|
        {
          'id' => i,
          'ts' => (BASE_TIME + i).strftime(DATETIME),
          'd' => (BASE_TIME + (i % 3650) * 86_400).strftime('%Y-%m-%d'),
          'name' => "name-#{i}",
          'country' => "country-#{i % 50}",
          'note' => i % 10 == 0 ? nil : "value-#{i}",
          'value' => i * 1.25 + 0.5,
          'amount' => i + 0.1234,
          'tags' => ["tag-#{i % 7}", "tag-#{i % 11}"],
          'attrs' => { 'clicks' => i, 'views' => i * 3 }
        }
      end
    end

    def create_table_sql(name)
      columns = MIXED_COLUMNS.map { |column, type| "#{column} #{type}" }.join(', ')
      "CREATE TABLE IF NOT EXISTS #{name} (#{columns}) ENGINE = MergeTree ORDER BY id"
    end
  end
end
