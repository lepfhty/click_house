RSpec.describe ClickHouse::Type::DateTimeType do
  describe '#serialize' do
    let(:time) do
      Time.new(2019, 1, 1, 9, 5, 6)
    end

    it 'works' do
      expect(subject.serialize(time)).to eq('2019-01-01 09:05:06')
    end
  end

  describe '#cast' do
    context 'when zone is empty' do
      let(:time) do
        Time.new(2019, 1, 1, 9, 5, 6)
      end

      it 'works' do
        expect(subject.cast('2019-01-01 09:05:06')).to eq(time)
      end

      it 'returns a plain Time in the process time zone' do
        got = subject.cast('2019-01-01 09:05:06')
        expect(got).to be_instance_of(Time)
        expect(got.utc_offset).to eq(time.utc_offset)
        expect(got.subsec).to eq(0)
      end

      it 'drops a fractional part' do
        expect(subject.cast('2019-01-01 09:05:06.789')).to eq(time)
      end

      it 'resolves DST gaps and overlaps like Time.local' do
        with_process_tz('America/New_York') do
          gap = subject.cast('2019-03-10 02:30:00')
          expect(gap).to eq(Time.local(2019, 3, 10, 2, 30, 0))
          expect(gap.utc_offset).to eq(Time.local(2019, 3, 10, 2, 30, 0).utc_offset)

          overlap = subject.cast('2019-11-03 01:30:00')
          expect(overlap).to eq(Time.local(2019, 11, 3, 1, 30, 0))
          expect(overlap.utc_offset).to eq(Time.local(2019, 11, 3, 1, 30, 0).utc_offset)
        end
      end
    end

    context 'when zone exists' do
      let(:time) do
        Time.new(2019, 1, 1, 9, 5, 6, Time.find_zone('Europe/Kyiv'))
      end

      it 'works' do
        expect(subject.cast('2019-01-01 09:05:06', 'Europe/Kyiv')).to eq(time)
      end

      it 'returns an ActiveSupport::TimeWithZone in that zone' do
        got = subject.cast('2019-01-01 09:05:06', 'Europe/Moscow')
        expect(got).to be_instance_of(ActiveSupport::TimeWithZone)
        expect(got.time_zone.name).to eq('Europe/Moscow')
        expect(got.inspect).to eq('Tue, 01 Jan 2019 09:05:06.000000000 MSK +03:00')
        expect(got.utc).to eq(Time.utc(2019, 1, 1, 6, 5, 6))
      end

      it 'resolves DST overlaps to the DST period like ActiveSupport::TimeZone#strptime' do
        expect(subject.cast('2019-11-03 01:30:00', 'America/New_York').inspect)
          .to eq('Sun, 03 Nov 2019 01:30:00.000000000 EDT -04:00')
      end

      it 'raises NoMethodError for an unknown zone' do
        expect { subject.cast('2019-01-01 09:05:06', 'Mars/Olympus') }.to raise_error(NoMethodError)
      end
    end

    context 'with invalid input' do
      it 'raises' do
        expect { subject.cast(nil) }.to raise_error(TypeError)
        expect { subject.cast(nil, 'UTC') }.to raise_error(TypeError)
        expect { subject.cast('2019-13-01 00:00:00') }.to raise_error(ArgumentError)
        expect { subject.cast('2019-13-01 00:00:00', 'UTC') }.to raise_error(ArgumentError)
      end
    end

    context 'when compared with strptime' do
      let(:format) { '%Y-%m-%d %H:%M:%S' }

      let(:values) do
        [
          '2019-01-01 09:05:06', '1970-01-01 00:00:00', '1900-01-01 00:00:00', '2106-02-07 06:28:15',
          '2299-12-31 23:59:59', '2019-01-01 09:05:06.789', '2019-01-01 09:05:06abc', '2019-01-01 09:05:06 ',
          "2019-01-01 09:05:06\n", '2019-1-1 9:5:6', '12019-01-01 09:05:06', '2019-01-01T09:05:06',
          ' 2019-01-01 09:05:06', '2019-02-29 00:00:00', '2020-02-29 00:00:00', '2019-02-30 12:00:00',
          '2019-04-31 00:00:00', '2019-12-31 24:00:00', '2019-12-31 24:00:01', '2019-12-31 23:59:60',
          '2019-13-01 00:00:00', '2019-00-10 00:00:00', '2019-01-32 00:00:00', '2019-01-00 00:00:00',
          '2019-01-01 23:60:00', '2019-01-01 25:00:00', '2019-03-10 02:30:00', '2019-11-03 01:30:00',
          '2019-03-31 03:30:00', '2019-10-27 03:30:00', '', 'garbage', nil, 1,
          '2019-01-01 09:05:06'.encode('UTF-16LE'), '2019-01-01 09:05:06'.b
        ]
      end

      it 'matches Time.strptime without a zone' do
        [nil, 'UTC', 'America/New_York', 'Europe/Kyiv'].each do |process_tz|
          with_process_tz(process_tz) do
            values.each do |value|
              expected = time_fingerprint { Time.strptime(value, format) }
              expect(time_fingerprint { subject.cast(value) }).to eq(expected), "#{value.inspect} in TZ=#{process_tz}"
            end
          end
        end
      end

      it 'matches ActiveSupport::TimeZone#strptime with a zone' do
        %w[UTC Europe/Moscow Europe/Kyiv America/New_York Asia/Kolkata Mars/Olympus].each do |tz|
          values.each do |value|
            expected = time_fingerprint { Time.find_zone(tz).strptime(value, format) }
            expect(time_fingerprint { subject.cast(value, tz) }).to eq(expected), "#{value.inspect} in #{tz}"
          end
        end
      end
    end
  end
end
