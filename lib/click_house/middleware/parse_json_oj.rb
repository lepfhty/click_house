# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ParseJsonOj < ResponseBase
      Faraday::Response.register_middleware self => self

      # @param env [Faraday::Env]
      def on_complete(env)
        return if error?(env) || !content_type?(env, content_type)

        env.body = Oj.load(env.body, load_options) unless blank_body?(env)
      end

      private

      def load_options
        config.parse_floats ? config.oj_load_options.merge(bigdecimal_load: :float) : config.oj_load_options
      end

      def on_setup
        require 'oj' unless defined?(Oj)
      end
    end
  end
end
