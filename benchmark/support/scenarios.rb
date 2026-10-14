# frozen_string_literal: true

module Bench
  # Scenario definitions. Offline scenarios exercise the driver's parsing, casting and
  # serialization code without a server; end-to-end scenarios go through HTTP.
  module Scenarios
    JSON_CONTENT_TYPE = 'application/json; charset=UTF-8'
    SELECT_TABLE = 'bench_select'
    INSERT_TABLE = 'bench_insert'
    SMALL_QUERIES = 200

    module_function

    def offline(config, rows)
      [parse_scenario(config, rows), *cast_scenarios(config, rows), *serialize_scenarios(config, rows)]
    end

    def end_to_end(connection, rows)
      insert_rows = Fixtures.insert_rows(rows)
      columns = Fixtures::MIXED_COLUMNS.keys
      compact_rows = insert_rows.map(&:values)
      truncate = -> { connection.execute("TRUNCATE TABLE #{INSERT_TABLE}") }
      select_sql = "SELECT * FROM #{SELECT_TABLE} ORDER BY id"

      [
        Scenario.new(
          suite: 'e2e', name: 'insert_json_each_row', rows: rows, setup: truncate,
          run: ->(_) { connection.insert(INSERT_TABLE, insert_rows) }
        ),
        Scenario.new(
          suite: 'e2e', name: 'insert_compact', rows: rows, setup: truncate,
          run: ->(_) { connection.insert(INSERT_TABLE, columns: columns, values: compact_rows) }
        ),
        Scenario.new(
          suite: 'e2e', name: 'select_all_raw', rows: rows,
          run: ->(_) { connection.select_all(select_sql).data }
        ),
        Scenario.new(
          suite: 'e2e', name: 'select_all_cast', rows: rows,
          run: ->(_) { connection.select_all(select_sql).to_a }
        ),
        Scenario.new(
          suite: 'e2e', name: "select_value_x#{SMALL_QUERIES}", rows: SMALL_QUERIES,
          run: ->(_) { SMALL_QUERIES.times { connection.select_value('SELECT 1') } }
        )
      ]
    end

    # Creates the end-to-end tables and fills the select table once per run
    def prepare_server(connection, database, rows)
      connection.execute("CREATE DATABASE IF NOT EXISTS #{database}", database: nil)
      [SELECT_TABLE, INSERT_TABLE].each do |table|
        connection.execute("DROP TABLE IF EXISTS #{table}")
        connection.execute(Fixtures.create_table_sql(table))
      end
      connection.insert(SELECT_TABLE, Fixtures.insert_rows(rows))
    end

    def parse_scenario(config, rows)
      body = Fixtures.select_body(Fixtures::MIXED_COLUMNS, rows)
      parser = parser(config)

      Scenario.new(
        suite: 'offline', name: 'parse_json_mixed', rows: rows,
        setup: -> { response_env(body) },
        run: ->(env) { parser.on_complete(env) }
      )
    end

    def cast_scenarios(config, rows)
      Fixtures::CAST_TYPES.keys.map do |type|
        body = Fixtures.select_body({ 'c' => type }, rows)

        Scenario.new(
          suite: 'offline', name: "cast #{type}", rows: rows,
          setup: -> { result_set(config, parse(config, body)) },
          run: ->(result_set) { result_set.to_a }
        )
      end
    end

    def serialize_scenarios(config, rows)
      parsed = parse(config, Fixtures.select_body(Fixtures::MIXED_COLUMNS, rows))
      schema = result_set(config, parsed)
      ruby_rows = result_set(config, parse(config, Fixtures.select_body(Fixtures::MIXED_COLUMNS, rows))).to_a
      insert_rows = Fixtures.insert_rows(rows)

      [
        Scenario.new(
          suite: 'offline', name: 'serialize_cast_mixed', rows: rows,
          run: ->(_) { schema.serialize(ruby_rows) }
        ),
        Scenario.new(
          suite: 'offline', name: 'dump_each_row_mixed', rows: rows,
          run: ->(_) { config.json_serializer.dump_each_row(insert_rows) }
        )
      ]
    end

    def parser(config)
      build_middleware(config.json_parser, nil, options: { config: config }, content_type: %r{application/json})
    end

    # Passes arguments the way Faraday's RackBuilder does. Faraday 1's DependencyLoader#new
    # only forwards keyword arguments on Ruby 3 when they arrive flagged by ruby2_keywords.
    def self.build_middleware(klass, *args)
      klass.new(*args)
    end
    singleton_class.send(:ruby2_keywords, :build_middleware)

    def response_env(body)
      Faraday::Env.from(
        body: body.dup,
        response_headers: Faraday::Utils::Headers.new('content-type' => JSON_CONTENT_TYPE)
      )
    end

    def parse(config, body)
      env = response_env(body)
      parser(config).on_complete(env)
      env.body
    end

    def result_set(config, parsed)
      ClickHouse::Response::ResultSet.new(
        config: config,
        meta: parsed.fetch(config.key('meta')),
        data: parsed.fetch(config.key('data')),
        summary: nil
      )
    end
  end
end
