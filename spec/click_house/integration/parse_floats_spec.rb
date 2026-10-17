# frozen_string_literal: true

RSpec.describe ClickHouse::Connection do
  subject do
    ClickHouse::Connection.new(ClickHouse.config.clone.assign(parse_floats: true))
  end

  before do
    subject.execute <<~SQL
      CREATE TABLE rspec(
          f Float64,
          d Decimal(38, 10),
          n Nullable(Decimal(38, 10)),
          a Array(Decimal(38, 10))
      ) ENGINE Memory
    SQL

    subject.execute <<~SQL
      INSERT INTO rspec VALUES (1.5, 1234567890123456789.0123456789, NULL, [0.1, 0.2])
    SQL
  end

  describe 'parse_floats' do
    it 'casts Float64 to Float and keeps Decimal precision' do
      got = subject.select_one('SELECT * FROM rspec')

      expect(got.fetch('f')).to be_an_instance_of(Float)
      expect(got.fetch('d')).to be_an_instance_of(BigDecimal)
      expect(got).to eq(
        'f' => 1.5,
        'd' => BigDecimal('1234567890123456789.0123456789'),
        'n' => nil,
        'a' => [BigDecimal('0.1'), BigDecimal('0.2')]
      )
    end

    it 'returns raw Float64 values as Float and Decimal values as strings' do
      got = subject.select_all('SELECT f, d FROM rspec').data.first

      expect(got.fetch('f')).to be_an_instance_of(Float)
      expect(got).to eq('f' => 1.5, 'd' => '1234567890123456789.0123456789')
    end

    it 'applies to execute with a JSON format' do
      got = subject.execute('SELECT f, d FROM rspec FORMAT JSON').body.fetch('data').first

      expect(got.fetch('f')).to be_an_instance_of(Float)
      expect(got).to eq('f' => 1.5, 'd' => '1234567890123456789.0123456789')
    end
  end
end
