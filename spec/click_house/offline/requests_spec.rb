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
