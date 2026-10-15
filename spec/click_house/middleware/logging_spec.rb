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

  context 'when the query is sent in the URL', :offline do
    subject(:connection) { stub_clickhouse(logger: Logger.new(log)) }

    # Simulates an environment where nothing has loaded the cgi library
    before do
      allow(CGI).to receive(:parse).and_raise(NameError, 'CGI.parse is not available') if defined?(CGI.parse)
    end

    [
      "SELECT 'a+b' AS plus",
      "SELECT '%&=?#' AS reserved",
      "SELECT 1; SELECT 2",
      "SELECT 'ünï 中' AS unicode",
    ].each do |sql|
      it "logs #{sql.inspect} as sent" do
        connection.execute(sql)
        expect(log.string).to include("#{sql};")
      end
    end

    it 'drops a trailing newline' do
      connection.execute("SELECT 1\n")
      expect(log.string).to include('SELECT 1;')
    end
  end
end
