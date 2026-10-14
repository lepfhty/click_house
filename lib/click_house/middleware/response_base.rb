# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ResponseBase < Faraday::Middleware
      CONTENT_TYPE_HEADER = 'content-type'

      attr_reader :options
      attr_reader :content_type

      def initialize(app = nil, options: {}, content_type: nil, preserve_raw: false)
        super(app)
        @options = options
        @content_type = content_type
        @preserve_raw = preserve_raw
        on_setup
      end

      # @return [Boolean]
      # @param env [Faraday::Env]
      # @param regexp [NilClass, Regexp]
      def content_type?(env, regexp)
        case regexp
        when NilClass
          false
        when Regexp
          regexp.match?(String(env[:response_headers][CONTENT_TYPE_HEADER]))
        else
          raise ArgumentError, "expected regexp got #{regexp.class}"
        end
      end

      # @return [Boolean]
      # true when ClickHouse reported an error. The body is the error text, which may not
      # match the content type (newer servers send text errors as application/json).
      # @param env [Faraday::Env]
      def error?(env)
        !env.success? || env.response_headers.include?(RaiseError::EXCEPTION_CODE_HEADER)
      end

      # @return [Config]
      def config
        options.fetch(:config)
      end

      private

      def on_setup
        # require external dependencies here
      end
    end
  end
end
