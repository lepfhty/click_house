# frozen_string_literal: true

RSpec.describe 'columns whose JSON values need no casting' do
  subject do
    ClickHouse.connection
  end

  # ResultSet skips casting these types, so the server's JSON must already be the cast result
  it 'returns the same values as the casters would' do
    got = subject.select_one(<<~SQL)
      SELECT
        'x' AS string,
        toFixedString('ab', 4) AS fixed,
        toUUID('61f0c404-5cb3-11e7-907b-a6006ad3dba0') AS uuid,
        CAST('a' AS Enum8('a' = 1)) AS enum,
        toLowCardinality('lc') AS lc,
        CAST(NULL AS Nullable(String)) AS null_string,
        ['a', 'b'] AS strings,
        [NULL, 'c']::Array(Nullable(String)) AS nullable_strings,
        CAST('b' AS Enum16('b' = 1000)) AS enum16,
        NULL AS nothing,
        CAST(NULL AS LowCardinality(Nullable(String))) AS lc_null,
        [] AS empty
    SQL

    expect(got).to eq(
      'string' => 'x',
      'fixed' => "ab\u0000\u0000",
      'uuid' => '61f0c404-5cb3-11e7-907b-a6006ad3dba0',
      'enum' => 'a',
      'lc' => 'lc',
      'null_string' => nil,
      'strings' => %w[a b],
      'nullable_strings' => [nil, 'c'],
      'enum16' => 'b',
      'nothing' => nil,
      'lc_null' => nil,
      'empty' => []
    )
  end
end
