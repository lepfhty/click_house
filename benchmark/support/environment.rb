# frozen_string_literal: true

require 'digest'
require 'etc'
require 'open3'
require 'time'

module Bench
  # Describes what is being benchmarked: the code (git), the runtime and dependencies,
  # and the machine. Every CSV row carries these columns.
  module Environment
    ROOT = File.expand_path('../..', __dir__)
    # Paths whose changes can affect results; results.csv is excluded so that appending
    # results doesn't mark the next run dirty
    PATHSPECS = ['lib', 'benchmark', '*.gemspec', 'Gemfile*', ':(exclude)benchmark/results.csv'].freeze

    module_function

    def capture(config:, parser:, note:)
      sha = git('rev-parse', '--short=12', 'HEAD')

      {
        run_id: "#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}-#{sha}",
        recorded_at: Time.now.utc.iso8601,
        git_sha: sha,
        git_branch: git('rev-parse', '--abbrev-ref', 'HEAD'),
        git_dirty: dirty?,
        git_diff_sha: diff_sha,
        gem_version: ClickHouse::VERSION,
        note: note,
        ruby_version: RUBY_VERSION,
        ruby_platform: RUBY_PLATFORM,
        yjit: yjit?,
        faraday_version: Faraday::VERSION,
        faraday_adapter: [config.adapter, gem_version('faraday-net_http')].compact.join(' '),
        json_parser: parser,
        json_version: JSON::VERSION,
        oj_version: gem_version('oj'),
        activesupport_version: gem_version('activesupport'),
        cpu: cpu,
        os: os
      }
    end

    def git(*args)
      out, status = Open3.capture2('git', '-C', ROOT, *args)
      status.success? ? out.strip : ''
    end

    def dirty?
      !git('status', '--porcelain', '--', *PATHSPECS).empty?
    end

    # Distinguishes runs made from different uncommitted states of the same commit
    def diff_sha
      return '' unless dirty?

      untracked = git('ls-files', '--others', '--exclude-standard', '--', *PATHSPECS).split("\n")
      contents = untracked.sort.map { |path| "#{path}\n#{File.read(File.join(ROOT, path))}" }
      Digest::SHA256.hexdigest([git('diff', 'HEAD', '--', *PATHSPECS), *contents].join("\n"))[0, 12]
    end

    def gem_version(name)
      Gem.loaded_specs[name]&.version&.to_s
    end

    def yjit?
      defined?(RubyVM::YJIT) && RubyVM::YJIT.respond_to?(:enabled?) ? RubyVM::YJIT.enabled? : false
    end

    def cpu
      model =
        if RUBY_PLATFORM.include?('darwin')
          `sysctl -n machdep.cpu.brand_string 2>/dev/null`.strip
        elsif File.exist?('/proc/cpuinfo')
          File.read('/proc/cpuinfo')[/^model name\s*:\s*(.+)$/, 1].to_s.strip
        end
      "#{model.to_s.empty? ? 'unknown' : model} x#{Etc.nprocessors}"
    end

    def os
      `uname -sr 2>/dev/null`.strip
    end
  end
end
