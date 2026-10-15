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

  # Plan node names differ between ClickHouse versions (22.9 reads with
  # `ReadFromStorage (TinyLog)`, 26.3 with `ReadFromStorageLog` and adds more
  # Expression steps), so this checks the tree's shape rather than its exact text.
  shared_examples 'a query plan' do
    let(:buffer) { StringIO.new }
    let!(:returned) { subject.explain(query, io: buffer) }
    let(:lines) { buffer.string.lines(chomp: true) }
    let(:join) { lines.index { |line| line.strip == 'Join (JOIN FillRightFirst)' } }
    let(:reads) { lines.each_index.select { |i| lines[i].strip.start_with?('ReadFromStorage') } }

    def indent(line)
      line[/\A */].size
    end

    it 'returns the plan written to io' do
      expect(returned).to eq(buffer.string)
    end

    it 'starts with the projection' do
      expect(lines.first).to start_with('Expression (')
    end

    it 'reads both sides of the join' do
      expect(join).not_to be_nil
      expect(reads.size).to eq(2)
      expect(reads).to all(be > join)
      expect(reads.map { |i| indent(lines[i]) }).to all(be > indent(lines[join]))
    end
  end

  context 'when normal query' do
    let(:query) { sql }

    it_behaves_like 'a query plan'
  end

  context 'when EXPLAIN query' do
    let(:query) { "EXPLAIN #{sql}" }

    it_behaves_like 'a query plan'

    it 'does not explain twice' do
      expect(subject.explain(query)).to eq(subject.explain(sql))
    end
  end
end
