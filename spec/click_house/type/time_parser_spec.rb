RSpec.describe ClickHouse::Type::TimeParser, :offline do
  let(:zone) { Time.find_zone('UTC') }

  describe '.parse' do
    it 'parses the layouts ClickHouse returns' do
      expect(described_class.parse('2019-01-01 09:05:06', nil, false)).to eq(Time.local(2019, 1, 1, 9, 5, 6))
      expect(described_class.parse('2019-01-01 09:05:06', zone, false)).to eq(Time.utc(2019, 1, 1, 9, 5, 6))
      expect(described_class.parse('2019-01-01 09:05:06.5', nil, true)).to eq(Time.local(2019, 1, 1, 9, 5, 6.5))
      expect(described_class.parse('2019-01-01 09:05:06.5', zone, true)).to eq(Time.utc(2019, 1, 1, 9, 5, 6.5))
    end

    it 'returns nil for anything else' do
      [
        nil, 1, '', '2019-01-01 09:05:06.5', '2019-1-1 9:5:6', '2019-01-01 24:00:00', '2019-01-01 23:59:60',
        '2019-13-01 00:00:00', '2019-01-01 09:05:06 ', "2019-01-01 09:05:06\n", '2019-01-01 09:05:06'.encode('UTF-16LE')
      ].each do |value|
        expect(described_class.parse(value, nil, false)).to be_nil, value.inspect
        expect(described_class.parse(value, zone, false)).to be_nil, value.inspect
      end

      [nil, '2019-01-01 09:05:06', '2019-01-01 09:05:06.', '2019-01-01 09:05:06.5a'].each do |value|
        expect(described_class.parse(value, nil, true)).to be_nil, value.inspect
        expect(described_class.parse(value, zone, true)).to be_nil, value.inspect
      end
    end
  end

  describe '.find_zone' do
    it 'returns the same zone as Time.find_zone' do
      expect(described_class.find_zone('Europe/Moscow')).to equal(Time.find_zone('Europe/Moscow'))
      expect(described_class.find_zone('Mars/Olympus')).to be_nil
    end
  end
end
