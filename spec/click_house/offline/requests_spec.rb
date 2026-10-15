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
end
