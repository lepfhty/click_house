# frozen_string_literal: true

require 'csv'

module Bench
  # Appends one CSV row per scenario result, prefixed with the environment columns.
  # New columns must be added at the end of HEADER so existing rows stay readable.
  class Recorder
    ENVIRONMENT_COLUMNS = %i[
      run_id recorded_at git_sha git_branch git_dirty git_diff_sha gem_version note
      ruby_version ruby_platform yjit faraday_version faraday_adapter json_parser
      json_version oj_version activesupport_version cpu os
    ].freeze
    RESULT_COLUMNS = %i[
      clickhouse_version suite scenario rows iterations
      wall_median_ms wall_min_ms cpu_median_ms allocations rows_per_sec
    ].freeze
    HEADER = (ENVIRONMENT_COLUMNS + RESULT_COLUMNS).map(&:to_s).freeze

    def initialize(path)
      @path = path
    end

    def append(environment, clickhouse_version, results)
      ensure_header!

      CSV.open(@path, 'a') do |csv|
        results.each do |result|
          values = environment.merge(result.to_h)
          values[:clickhouse_version] = result.suite == 'e2e' ? clickhouse_version : nil
          csv << HEADER.map { |column| values[column.to_sym] }
        end
      end
    end

    private

    def ensure_header!
      if !File.exist?(@path) || File.zero?(@path)
        CSV.open(@path, 'w') { |csv| csv << HEADER }
        return
      end

      existing = CSV.open(@path, &:shift)
      return if existing == HEADER

      raise "#{@path} has a different header than Bench::Recorder::HEADER. " \
            'Add new columns at the end and backfill existing rows.'
    end
  end
end
