RSpec.describe ClickHouse::Type::DateTimeType do
  subject do
    ClickHouse.connection
  end

  before do
    subject.execute <<~SQL
      CREATE TABLE rspec(
          a DateTime,
          b DateTime('Europe/Kyiv'),
          c Nullable(DateTime),
          d Nullable(DateTime('Europe/Kyiv')),
          e Nullable(DateTime),
       ) ENGINE Memory
    SQL
  end

  describe 'cast' do
    before do
      subject.execute <<~SQL
        INSERT INTO rspec VALUES (
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
          toDateTime('2019-01-01 09:05:06') AS a,
          toDateTime('2019-01-01 09:05:06', 'Europe/Moscow') AS b,
          toDateTime('2019-11-03 05:30:00', 'UTC') AS c,
          toTimeZone(toDateTime('2019-11-03 05:30:00', 'UTC'), 'America/New_York') AS d,
          toNullable(toDateTime('2019-01-01 09:05:06', 'UTC')) AS e,
          CAST(NULL AS Nullable(DateTime('UTC'))) AS f
      SQL

      expect(got.fetch('a')).to be_instance_of(Time)
      expect(got.fetch('b')).to be_instance_of(ActiveSupport::TimeWithZone)
      expect(got.fetch('b').inspect).to eq('Tue, 01 Jan 2019 09:05:06.000000000 MSK +03:00')
      expect(got.fetch('c').inspect).to eq('Sun, 03 Nov 2019 05:30:00.000000000 UTC +00:00')
      expect(got.fetch('d').inspect).to eq('Sun, 03 Nov 2019 01:30:00.000000000 EDT -04:00')
      expect(got.fetch('e').inspect).to eq('Tue, 01 Jan 2019 09:05:06.000000000 UTC +00:00')
      expect(got.fetch('f')).to be_nil
    end
  end

  describe 'serialize' do
    let(:row) do
      {
        'a' => Time.now.round,
        'b' => Time.find_zone("Europe/Kyiv").now.round,
        'c' => Time.now.round,
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
      expect(got.fetch('d')).to eq(nil)
      expect(got.fetch('e')).to eq(nil)
    end
  end
end
