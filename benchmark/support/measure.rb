# frozen_string_literal: true

module Bench
  Scenario = Struct.new(:suite, :name, :rows, :setup, :run, keyword_init: true)
  Result = Struct.new(
    :suite, :scenario, :rows, :iterations,
    :wall_median_ms, :wall_min_ms, :cpu_median_ms, :allocations, :rows_per_sec,
    keyword_init: true
  )

  # Runs a scenario's warmup and timed iterations. `setup` runs before every iteration,
  # outside the timed section, and its return value is passed to `run`.
  class Measure
    def initialize(iterations:, warmup:)
      @iterations = iterations
      @warmup = warmup
    end

    # @return [Result]
    def call(scenario)
      @warmup.times { scenario.run.call(prepare(scenario)) }

      samples = Array.new(@iterations) { sample(scenario) }
      wall = median(samples.map { |s| s[:wall] })

      Result.new(
        suite: scenario.suite,
        scenario: scenario.name,
        rows: scenario.rows,
        iterations: @iterations,
        wall_median_ms: ms(wall),
        wall_min_ms: ms(samples.map { |s| s[:wall] }.min),
        cpu_median_ms: ms(median(samples.map { |s| s[:cpu] })),
        allocations: median(samples.map { |s| s[:allocations] }),
        rows_per_sec: (scenario.rows / wall).round
      )
    end

    private

    def prepare(scenario)
      scenario.setup&.call
    end

    def sample(scenario)
      input = prepare(scenario)
      GC.start

      allocations = GC.stat(:total_allocated_objects)
      wall = clock(Process::CLOCK_MONOTONIC)
      cpu = clock(Process::CLOCK_PROCESS_CPUTIME_ID)
      scenario.run.call(input)

      {
        cpu: clock(Process::CLOCK_PROCESS_CPUTIME_ID) - cpu,
        wall: clock(Process::CLOCK_MONOTONIC) - wall,
        allocations: GC.stat(:total_allocated_objects) - allocations
      }
    end

    def clock(id)
      Process.clock_gettime(id)
    end

    def median(values)
      sorted = values.sort
      mid = sorted.length / 2
      sorted.length.odd? ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2.0
    end

    def ms(seconds)
      (seconds * 1000).round(2)
    end
  end
end
