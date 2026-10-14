RSpec.describe ClickHouse::Middleware::Logging do
  subject do
    ClickHouse::Connection.new(ClickHouse.config.clone.assign(logger: Logger.new(log)))
  end

  let(:log) { StringIO.new }

  context 'when the query succeeds' do
    it 'logs the query' do
      subject.select_all('SELECT 1 AS logged_value')
      expect(log.string).to include('SELECT 1 AS logged_value')
    end
  end

  context 'when the query fails' do
    it 'logs the query and raises' do
      expect { subject.select_all('SELECT * FROM missing_logged_table') }.to raise_error(ClickHouse::DbException)
      expect(log.string).to include('SELECT * FROM missing_logged_table')
    end
  end
end
