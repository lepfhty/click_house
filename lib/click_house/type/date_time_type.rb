# frozen_string_literal: true

module ClickHouse
  module Type
    class DateTimeType < BaseType
      FORMAT = '%Y-%m-%d %H:%M:%S'

      def cast(value, tz = nil)
        if tz
          zone = TimeParser.find_zone(tz)
          (zone && TimeParser.parse(value, zone, false)) || zone.strptime(value, FORMAT)
        else
          TimeParser.parse(value, nil, false) || Time.strptime(value, FORMAT)
        end
      end

      def serialize(value, *)
        value.strftime(FORMAT)
      end
    end
  end
end
