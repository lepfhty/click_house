RSpec.describe ClickHouse::Type::DateTime64Type do
  subject do
    ClickHouse.connection
  end

  before do
    subject.execute <<~SQL
      CREATE TABLE rspec(
          a DateTime64(0),
          b DateTime64(9, 'Europe/Kyiv'),
          c Nullable(DateTime64(9)),
          d Nullable(DateTime64(9, 'Europe/Kyiv')),
          e Nullable(DateTime64(9)),
       ) ENGINE Memory
    SQL
  end

  describe 'cast' do
    before do
      subject.execute <<~SQL
        INSERT INTO rspec values (
          now(),
          now(),
          now(),
          now(),
          null
        );
      SQL
    end

    it 'works' do
      got = subject.select_one('SELECT * FROM rspec')
      expect(got.fetch('a')).to be_a(Time)
      expect(got.fetch('a')).to have_attributes(zone: Time.now.zone)

      expect(got.fetch('b')).to be_a(Time)
      expect(got.fetch('b')).to have_attributes(zone: Time.find_zone('Europe/Kyiv').tzinfo.abbr)

      expect(got.fetch('c')).to be_a(Time)
      expect(got.fetch('d')).to be_a(Time)
      expect(got.fetch('d')).to have_attributes(zone: Time.find_zone('Europe/Kyiv').tzinfo.abbr)

      expect(got.fetch('e')).to be_a(NilClass)
    end
  end

  describe 'cast exact values' do
    it 'works' do
      got = subject.select_one(<<~SQL)
        SELECT
          toDateTime64('2019-01-01 09:05:06', 0) AS a,
          toDateTime64('2019-01-01 09:05:06.123', 3, 'Europe/Moscow') AS b,
          toDateTime64('2019-01-01 09:05:06.123456', 6, 'UTC') AS c,
          toDateTime64('2019-01-01 09:05:06.123456789', 9, 'UTC') AS d,
          toDateTime64('2019-01-01 09:05:06.000000001', 9) AS e,
          toNullable(toDateTime64('2019-01-01 09:05:06.5', 3, 'UTC')) AS f,
          CAST(NULL AS Nullable(DateTime64(3, 'UTC'))) AS g
      SQL

      expect(got.fetch('a')).to be_instance_of(Time)
      expect(got.fetch('a').subsec).to eq(0)
      expect(got.fetch('b')).to be_instance_of(ActiveSupport::TimeWithZone)
      expect(got.fetch('b').inspect).to eq('Tue, 01 Jan 2019 09:05:06.123000000 MSK +03:00')
      expect(got.fetch('c').inspect).to eq('Tue, 01 Jan 2019 09:05:06.123456000 UTC +00:00')
      expect(got.fetch('d').inspect).to eq('Tue, 01 Jan 2019 09:05:06.123456789 UTC +00:00')
      expect(got.fetch('e')).to be_instance_of(Time)
      expect(got.fetch('e').nsec).to eq(1)
      expect(got.fetch('f').subsec).to eq(Rational(1, 2))
      expect(got.fetch('g')).to be_nil
    end
  end

  describe 'serialize' do
    let(:row) do
      {
        'a' => Time.now.round,
        'b' => Time.find_zone("Europe/Kyiv").now,
        'c' => Time.now,
        'd' => nil,
        'e' => nil,
      }
    end

    it 'works' do
      subject.insert('rspec', subject.table_schema('rspec').serialize_one(row))
      got = subject.select_one('SELECT * FROM rspec')

      expect(got.fetch('a')).to eq(row.fetch('a'))
      expect(got.fetch('b')).to eq(row.fetch('b'))
      expect(got.fetch('c')).to eq(row.fetch('c'))
      expect(got.fetch('d')).to eq(row.fetch('d'))
      expect(got.fetch('e')).to eq(row.fetch('e'))
    end
  end
end
