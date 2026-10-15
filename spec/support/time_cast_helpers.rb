# frozen_string_literal: true

module TimeCastHelpers
  # Everything a caller can observe about a cast result, or the error it raised
  def time_fingerprint
    value = yield
    zone_name = value.time_zone.name if value.respond_to?(:time_zone)
    [value.class, value.inspect, value.to_r, value.utc_offset, value.zone, zone_name, value.utc.inspect]
  rescue StandardError => e
    [e.class, e.message]
  end

  # Runs the block with the process time zone (ENV['TZ']) set to tz
  def with_process_tz(tz)
    previous = ENV.fetch('TZ', nil)
    ENV['TZ'] = tz
    yield
  ensure
    ENV['TZ'] = previous
  end
end

RSpec.configure do |config|
  config.include TimeCastHelpers
end
