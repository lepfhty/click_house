RSpec.describe 'requests without a server', :offline do
  subject(:connection) { stub_clickhouse(body: '{"meta": [], "data": []}', database: 'metrics') }

  let(:request) { clickhouse_requests.last }

  it 'sends selects as a GET with the SQL in the body' do
    connection.select_all('SELECT 1')

    expect(request).to have_attributes(method: :get, path: '/', body: 'SELECT 1')
    expect(request.params).to eq(
      'default_format' => 'JSON',
      'database' => 'metrics',
      'send_progress_in_http_headers' => '1'
    )
  end

  it 'sends execute as a POST with the SQL in the query params' do
    connection.execute('INSERT INTO t VALUES', '(1)', params: { mutations_sync: 1 })

    expect(request).to have_attributes(method: :post, path: '/', body: '(1)')
    expect(request.params).to eq(
      'query' => 'INSERT INTO t VALUES',
      'database' => 'metrics',
      'mutations_sync' => '1',
      'send_progress_in_http_headers' => '1'
    )
  end

  context 'with global_params' do
    subject(:connection) do
      stub_clickhouse(body: '{"meta": [], "data": []}', database: 'metrics', global_params: { max_threads: 2, mutations_sync: 1 })
    end

    it 'sends them with selects' do
      connection.select_all('SELECT 1')

      expect(request.params).to include('max_threads' => '2', 'mutations_sync' => '1')
    end

    it 'sends them with execute' do
      connection.execute('SELECT 1')

      expect(request.params).to include('max_threads' => '2', 'mutations_sync' => '1')
    end

    it 'lets per-request params win on GET' do
      connection.get(body: 'SELECT 1', query: { max_threads: 4 })

      expect(request.params).to include('max_threads' => '4', 'mutations_sync' => '1')
    end

    it 'sends no params with ping' do
      connection.ping

      expect(request).to have_attributes(path: '/ping', params: {})
    end

    it 'sends no params with replicas_status' do
      connection.replicas_status

      expect(request).to have_attributes(path: '/replicas_status', params: {})
    end
  end

  describe 'overriding send_progress_in_http_headers' do
    [[:get, ->(c) { c.select_all('SELECT 1') }], [:post, ->(c) { c.execute('SELECT 1') }]].each do |method, run|
      it "removes it on #{method.upcase} with a nil global param" do
        run.call(stub_clickhouse(body: '{"meta": [], "data": []}', global_params: { send_progress_in_http_headers: nil }))

        expect(request.params).not_to have_key('send_progress_in_http_headers')
      end

      it "sends 0 on #{method.upcase} with a 0 global param" do
        run.call(stub_clickhouse(body: '{"meta": [], "data": []}', global_params: { send_progress_in_http_headers: 0 }))

        expect(request.params).to include('send_progress_in_http_headers' => '0')
      end
    end

    it 'sends a per-request value on GET' do
      connection.get(body: 'SELECT 1', query: { send_progress_in_http_headers: 0 })

      expect(request.params).to include('send_progress_in_http_headers' => '0')
    end
  end

  describe 'parse_floats' do
    [[:get, ->(c) { c.select_all('SELECT 1') }], [:post, ->(c) { c.execute('SELECT 1') }]].each do |method, run|
      it "asks for quoted decimals on #{method.upcase}" do
        run.call(stub_clickhouse(body: '{"meta": [], "data": []}', parse_floats: true))

        expect(request.params).to include('output_format_json_quote_decimals' => '1')
      end

      it "lets a nil global param remove quoted decimals on #{method.upcase}" do
        run.call(stub_clickhouse(
          body: '{"meta": [], "data": []}',
          parse_floats: true,
          global_params: { output_format_json_quote_decimals: nil }
        ))

        expect(request.params).not_to have_key('output_format_json_quote_decimals')
      end
    end

    it 'lets a nil per-request param remove quoted decimals on POST' do
      stub_clickhouse(parse_floats: true).execute('SELECT 1', params: { output_format_json_quote_decimals: nil })

      expect(request.params).not_to have_key('output_format_json_quote_decimals')
    end

    it 'sends no params with ping' do
      stub_clickhouse(parse_floats: true).ping

      expect(request.params).to eq({})
    end
  end

  describe 'database precedence' do
    subject(:connection) do
      stub_clickhouse(body: '{"meta": [], "data": []}', database: 'cfg', global_params: { database: 'gp' })
    end

    it 'sends config.database over global_params on GET' do
      connection.select_all('SELECT 1')

      expect(request.params).to include('database' => 'cfg')
    end

    it 'sends config.database over global_params on POST' do
      connection.execute('SELECT 1')

      expect(request.params).to include('database' => 'cfg')
    end

    it 'sends the database argument over per-request params on GET' do
      connection.get(body: 'SELECT 1', database: 'arg', query: { database: 'per_call' })

      expect(request.params).to include('database' => 'arg')
    end

    it 'sends the database argument over per-request params on POST' do
      connection.execute('SELECT 1', database: 'arg', params: { database: 'per_call' })

      expect(request.params).to include('database' => 'arg')
    end

    it 'sends no database on GET when the argument is nil' do
      connection.get(body: 'SELECT 1', database: nil)

      expect(request.params).not_to have_key('database')
    end

    it 'sends no database on POST when the argument is nil' do
      connection.databases

      expect(request.params).not_to have_key('database')
    end

    it 'still sends other per-request params on POST' do
      connection.execute('SELECT 1', params: { max_threads: 4 })

      expect(request.params).to include('max_threads' => '4', 'database' => 'cfg')
    end
  end

  it 'uses a config that shares no mutable state with the global one' do
    global = ClickHouse.config
    config = connection.config
    shared = %i[headers global_params oj_load_options oj_dump_options json_load_options].select do |name|
      config.public_send(name).equal?(global.public_send(name))
    end

    expect(shared).to be_empty
    expect(config.json_serializer.config).to equal(config)
  end
end
