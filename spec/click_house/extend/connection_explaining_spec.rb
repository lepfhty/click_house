RSpec.describe ClickHouse::Extend::ConnectionExplaining do
  subject do
    ClickHouse.connection
  end

  before do
    subject.execute <<~SQL
      CREATE TABLE rspec(id Int64) ENGINE TinyLog
    SQL
  end

  let(:sql) do
    'SELECT 1 FROM rspec CROSS JOIN rspec'
  end

  let(:expectation) do
    subject.execute("EXPLAIN #{sql}").body
  end

  it 'returns a query plan' do
    expect(expectation).to include('Join')
  end

  context 'when normal query' do
    it 'works' do
      buffer = StringIO.new
      subject.explain(sql, io: buffer)
      expect(buffer.string).to eq(expectation)
    end
  end

  context 'when EXPLAIN query' do
    it 'works' do
      buffer = StringIO.new
      subject.explain("EXPLAIN #{sql}", io: buffer)
      expect(buffer.string).to eq(expectation)
    end
  end
end
