# frozen_string_literal: true

require 'concurrent/map'

module ClickHouse
  module Type
    # Builds times from ClickHouse's "YYYY-MM-DD hh:mm:ss[.fff…]" output by slicing integers,
    # passing the same arguments to the same constructors as Time.strptime and
    # ActiveSupport::TimeZone#strptime. Returns nil for any other input so callers fall back to strptime.
    module TimeParser
      DATE_TIME = '\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01]) (?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d'
      SECONDS_RE = /\A#{DATE_TIME}\z/.freeze
      FRACTION_RE = /\A#{DATE_TIME}\.\d+\z/.freeze
      FRACTION_OFFSET = 20
      USEC_PER_SEC = 1_000_000
      ZONES = Concurrent::Map.new

      module_function

      # @return [ActiveSupport::TimeZone, nil]
      # @param tz [String]
      def find_zone(tz)
        ZONES.fetch_or_store(tz) { Time.find_zone(tz) }
      end

      # @return [Time, ActiveSupport::TimeWithZone, nil]
      # @param value [String]
      # @param zone [ActiveSupport::TimeZone, nil] nil for the process time zone
      # @param fraction [Boolean] true if value has fractional seconds
      def parse(value, zone, fraction)
        fraction ? parse_fraction(value, zone) : parse_seconds(value, zone)
      end

      # @param value [String] like "2019-01-01 09:05:06"
      def parse_seconds(value, zone)
        return unless layout?(value, SECONDS_RE)

        year, mon, day, hour, min, sec = components(value)
        if zone
          zone.local(year, mon, day, hour, min, sec)
        else
          Time.local(year, mon, day, hour, min, sec, 0)
        end
      end

      # @param value [String] like "2019-01-01 09:05:06.123"
      def parse_fraction(value, zone)
        return unless layout?(value, FRACTION_RE)

        year, mon, day, hour, min, sec = components(value)
        digits = value.length - FRACTION_OFFSET
        fraction = Rational(value[FRACTION_OFFSET, digits].to_i, 10**digits)
        if zone
          zone.local(year, mon, day, hour, min, sec + fraction)
        else
          Time.local(year, mon, day, hour, min, sec, fraction * USEC_PER_SEC)
        end
      end

      def layout?(value, regexp)
        value.is_a?(String) && value.ascii_only? && regexp.match?(value)
      end

      def components(value)
        [value[0, 4].to_i, value[5, 2].to_i, value[8, 2].to_i, value[11, 2].to_i, value[14, 2].to_i, value[17, 2].to_i]
      end
    end
  end
end
