RSpec.describe ClickHouse::Type::DateTime64Type, :offline do
  let(:precisions) do
    (0..9).to_a
  end

  describe '#serialize' do
    let(:time) do
      Time.new(2019, 1, 1, 9, 5, 6)
    end

    it 'works' do
      precisions.each do |precision|
        tail = "." + "0" * precision if precision > 0
        expect(subject.serialize(time, precision)).to eq("2019-01-01 09:05:06#{tail}")
      end
    end
  end

  describe '#cast' do
    context 'when zone is empty' do
      let(:time) do
        Time.new(2019, 1, 1, 9, 5, 6)
      end

      it 'works' do
        expect(subject.cast('2019-01-01 09:05:06.0000')).to eq(time)
      end

      it 'returns a plain Time in the process time zone' do
        got = subject.cast('2019-01-01 09:05:06', 0)
        expect(got).to be_instance_of(Time)
        expect(got).to eq(time)
        expect(got.utc_offset).to eq(time.utc_offset)
      end

      it 'keeps the fractional part exactly' do
        expect(subject.cast('2019-01-01 09:05:06.123', 3).subsec).to eq(Rational(123, 1000))
        expect(subject.cast('2019-01-01 09:05:06.123456', 6).subsec).to eq(Rational(123_456, 1_000_000))
        expect(subject.cast('2019-01-01 09:05:06.123456789', 9).subsec).to eq(Rational(123_456_789, 1_000_000_000))
        expect(subject.cast('2019-01-01 09:05:06.000000001', 9).nsec).to eq(1)
        expect(subject.cast('2019-01-01 09:05:06.000', 3)).to eq(time)
      end

      it 'reads as many fractional digits as given, whatever the precision' do
        expect(subject.cast('2019-01-01 09:05:06.12', 9).subsec).to eq(Rational(12, 100))
        expect(subject.cast('2019-01-01 09:05:06.123456789', 3).subsec).to eq(Rational(123_456_789, 1_000_000_000))
      end

      it 'drops a fractional part when precision is 0' do
        expect(subject.cast('2019-01-01 09:05:06.789', 0)).to eq(time)
      end

      it 'requires a fractional part when precision is positive' do
        expect { subject.cast('2019-01-01 09:05:06', 3) }.to raise_error(ArgumentError)
      end
    end

    context 'when zone exists' do
      let(:time) do
        Time.new(2019, 1, 1, 9, 5, 6, Time.find_zone('Europe/Kyiv'))
      end

      it 'works' do
        expect(subject.cast('2019-01-01 09:05:06', 0, 'Europe/Kyiv').to_s).to eq(time.to_s)
        expect(subject.cast('2019-01-01 09:05:06.00', 9, 'Europe/Kyiv').to_s).to eq(time.to_s)
      end

      it 'returns an ActiveSupport::TimeWithZone in that zone' do
        got = subject.cast('2019-01-01 09:05:06.123456789', 9, 'Europe/Moscow')
        expect(got).to be_instance_of(ActiveSupport::TimeWithZone)
        expect(got.time_zone.name).to eq('Europe/Moscow')
        expect(got.inspect).to eq('Tue, 01 Jan 2019 09:05:06.123456789 MSK +03:00')
        expect(got.utc).to eq(Time.utc(2019, 1, 1, 6, 5, Rational(6_123_456_789, 1_000_000_000)))
      end

      it 'keeps the fractional part exactly' do
        expect(subject.cast('2019-01-01 09:05:06', 0, 'UTC').subsec).to eq(0)
        expect(subject.cast('2019-01-01 09:05:06.123', 3, 'UTC').subsec).to eq(Rational(123, 1000))
        expect(subject.cast('2019-01-01 09:05:06.123456', 6, 'UTC').subsec).to eq(Rational(123_456, 1_000_000))
        expect(subject.cast('2019-01-01 09:05:06.000000001', 9, 'UTC').nsec).to eq(1)
      end
    end

    context 'with invalid input' do
      it 'raises' do
        expect { subject.cast(nil) }.to raise_error(TypeError)
        expect { subject.cast(nil, 3, 'UTC') }.to raise_error(TypeError)
        expect { subject.cast('2019-13-01 00:00:00.000', 3) }.to raise_error(ArgumentError)
        expect { subject.cast('2019-01-01 09:05:06.000', 3, 'Mars/Olympus') }.to raise_error(NoMethodError)
      end
    end

    context 'when compared with strptime' do
      let(:values) do
        [
          '2019-01-01 09:05:06', '2019-01-01 09:05:06.1', '2019-01-01 09:05:06.123', '2019-01-01 09:05:06.123456',
          '2019-01-01 09:05:06.123456789', '2019-01-01 09:05:06.000000001', '2019-01-01 09:05:06.000',
          '2019-01-01 09:05:06.1234567891234', '1900-01-01 00:00:00.000', '1969-12-31 23:59:59.999999999',
          '2299-12-31 23:59:59.999999999', '2019-01-01 09:05:06.', '2019-01-01 09:05:06.12a', '2019-01-01 09:05:06.-1',
          '2019-01-01 09:05:06.123 ', "2019-01-01 09:05:06.123\n", '2019-1-1 9:5:6.5', '2019-02-30 12:00:00.250',
          '2019-12-31 24:00:00.000', '2019-12-31 23:59:60.500', '2019-13-01 00:00:00.000', '2019-01-01 23:60:00.000',
          '2019-03-10 02:30:00.500', '2019-11-03 01:30:00.500', '2019-10-27 03:30:00.500', '', nil, 1,
          '2019-01-01 09:05:06.123'.encode('UTF-16LE'), '2019-01-01 09:05:06.123'.b
        ]
      end

      def reference_format(precision)
        precision.zero? ? '%Y-%m-%d %H:%M:%S' : '%Y-%m-%d %H:%M:%S.%N'
      end

      it 'matches Time.strptime without a zone' do
        [nil, 'UTC', 'America/New_York', 'Europe/Kyiv'].each do |process_tz|
          with_process_tz(process_tz) do
            [0, 3, 6, 9].product(values).each do |precision, value|
              expected = time_fingerprint { Time.strptime(value, reference_format(precision)) }
              expect(time_fingerprint { subject.cast(value, precision) })
                .to eq(expected), "#{value.inspect} (#{precision}) in TZ=#{process_tz}"
            end
          end
        end
      end

      it 'matches ActiveSupport::TimeZone#strptime with a zone' do
        %w[UTC Europe/Moscow Europe/Kyiv America/New_York Asia/Kolkata Mars/Olympus].each do |tz|
          [0, 3, 6, 9].product(values).each do |precision, value|
            expected = time_fingerprint { Time.find_zone(tz).strptime(value, reference_format(precision)) }
            expect(time_fingerprint { subject.cast(value, precision, tz) })
              .to eq(expected), "#{value.inspect} (#{precision}) in #{tz}"
          end
        end
      end
    end
  end
end
