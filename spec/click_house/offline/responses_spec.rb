RSpec.describe 'responses without a server', :offline do
  def json_body(rows)
    JSON.generate(
      meta: [{ name: 'big', type: 'UInt64' }, { name: 'small', type: 'Int64' }, { name: 's', type: 'String' }],
      data: rows,
      rows: rows.size,
      statistics: { elapsed: 0.0002, rows_read: 1, bytes_read: 1 }
    )
  end

  describe 'type casting' do
    let(:expected) { [{ 'big' => 18_446_744_073_709_551_615, 'small' => -5, 's' => 'x' }] }

    it 'casts quoted 64-bit integers (before 26.x)' do
      connection = stub_clickhouse(body: json_body([{ big: '18446744073709551615', small: '-5', s: 'x' }]))
      expect(connection.select_all('SELECT 1').to_a).to eq(expected)
    end

    it 'casts unquoted 64-bit integers (26.x)' do
      connection = stub_clickhouse(body: json_body([{ big: 18_446_744_073_709_551_615, small: -5, s: 'x' }]))
      expect(connection.select_all('SELECT 1').to_a).to eq(expected)
    end

    it 'symbolizes keys when configured' do
      connection = stub_clickhouse(body: json_body([{ big: '1', small: '2', s: 'x' }]), symbolize_keys: true)
      expect(connection.select_one('SELECT 1')).to eq({ big: 1, small: 2, s: 'x' })
    end
  end

  describe 'parse_floats' do
    let(:body) do
      JSON.generate(
        meta: [{ name: 'f', type: 'Float64' }, { name: 'd', type: 'Decimal(38, 10)' }],
        data: [{ f: 0.1, d: '1234567890123456789.0123456789' }]
      )
    end

    it 'parses floats as Float' do
      connection = stub_clickhouse(body: body, parse_floats: true)
      row = connection.select_all('SELECT 1').data.first

      expect(row.fetch('f')).to be_an_instance_of(Float)
      expect(row.fetch('d')).to eq('1234567890123456789.0123456789')
    end

    it 'casts quoted decimals to BigDecimal' do
      connection = stub_clickhouse(body: body, parse_floats: true)
      row = connection.select_one('SELECT 1')

      expect(row.fetch('f')).to be_an_instance_of(Float).and eq(0.1)
      expect(row.fetch('d')).to be_an_instance_of(BigDecimal).and eq(BigDecimal('1234567890123456789.0123456789'))
    end

    it 'works with symbolize_keys' do
      connection = stub_clickhouse(body: body, parse_floats: true, symbolize_keys: true)
      row = connection.select_all('SELECT 1').data.first

      expect(row.keys).to eq(%i[f d])
      expect(row.fetch(:f)).to be_an_instance_of(Float)
    end

    it 'leaves the configured load options unchanged' do
      connection = stub_clickhouse(body: body, parse_floats: true)
      json_options = connection.config.json_load_options.dup
      oj_options = connection.config.oj_load_options.dup
      connection.select_all('SELECT 1')

      expect(connection.config).to have_attributes(json_load_options: json_options, oj_load_options: oj_options)
    end

    it 'parses floats as BigDecimal by default' do
      connection = stub_clickhouse(body: body)

      expect(connection.select_all('SELECT 1').data.first.fetch('f')).to be_an_instance_of(BigDecimal)
    end
  end

  describe 'summary' do
    let(:summary_header) do
      '{"read_rows":"3","read_bytes":"24","written_rows":"1","written_bytes":"8",' \
        '"total_rows_to_read":"3","result_rows":"1","result_bytes":"8"}'
    end

    it 'parses X-ClickHouse-Summary and the body statistics' do
      connection = stub_clickhouse(
        headers: StubClickHouse::JSON_HEADERS.merge('X-ClickHouse-Summary' => summary_header),
        body: json_body([])
      )
      summary = connection.select_all('SELECT 1').summary

      expect(summary).to have_attributes(
        read_rows: 3, read_bytes: 24, written_rows: 1, written_bytes: 8,
        total_rows_to_read: 3, result_rows: 1, result_bytes: 8, elapsed: 0.0002
      )
    end
  end

  describe 'errors' do
    let(:error_text) do
      "Code: 395. DB::Exception: boom: while executing 'FUNCTION throwIf(...)'. " \
        "(FUNCTION_THROW_IF_VALUE_IS_NON_ZERO) (version 26.3.51.7 (official build))\n"
    end

    it 'raises DbException when the exception header comes with a 200 status' do
      connection = stub_clickhouse(
        headers: StubClickHouse::JSON_HEADERS.merge('X-ClickHouse-Exception-Code' => '395'),
        body: error_text
      )
      expect { connection.select_all('SELECT 1') }.to raise_error(ClickHouse::DbException, "[200] #{error_text}")
    end

    it 'raises DbException with the error text for a 404 sent as application/json (23.5+)' do
      text = "Code: 60. DB::Exception: Unknown table expression identifier 'nope'. (UNKNOWN_TABLE)\n"
      connection = stub_clickhouse(
        status: 404,
        headers: StubClickHouse::JSON_HEADERS.merge('X-ClickHouse-Exception-Code' => '60'),
        body: text
      )
      expect { connection.select_all('SELECT * FROM nope') }.to raise_error(ClickHouse::DbException, "[404] #{text}")
    end

    context 'when a query fails after some rows were written' do
      let(:partial_json) { "{\n\t\"meta\": [{\"name\": \"number\", \"type\": \"UInt64\"}],\n\t\"data\":\n\t[\n\t\t{\"number\": 0}" }

      it 'raises DbException with only the error text' do
        pending 'the message includes the partial JSON body (doc/performance/07, existing gaps)'

        connection = stub_clickhouse(
          status: 500,
          headers: StubClickHouse::JSON_HEADERS.merge('X-ClickHouse-Exception-Code' => '395'),
          body: partial_json + error_text
        )
        expect { connection.select_all('SELECT 1') }.to raise_error(ClickHouse::DbException, "[500] #{error_text}")
      end

      it 'raises DbException when 26.x writes the error after sending the headers' do
        pending 'the __exception__ block is parsed as JSON and raises a parser error'

        tag = 'hciqwermngrtqoox'
        connection = stub_clickhouse(
          headers: StubClickHouse::JSON_HEADERS.merge('X-ClickHouse-Exception-Tag' => tag),
          body: "#{partial_json}\n__exception__\n#{tag}\n#{error_text}#{error_text.bytesize} #{tag}\n__exception__\n"
        )
        expect { connection.select_all('SELECT 1') }.to raise_error(ClickHouse::DbException, /Code: 395/)
      end
    end
  end
end
