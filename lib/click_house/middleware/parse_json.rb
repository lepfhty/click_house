# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ParseJson < ResponseBase
      Faraday::Response.register_middleware self => self

      # @param env [Faraday::Env]
      def on_complete(env)
        return if error?(env) || !content_type?(env, content_type)

        env.body = JSON.parse(env.body, **load_options) unless blank_body?(env)
      end

      private

      def load_options
        config.parse_floats ? config.json_load_options.merge(decimal_class: nil) : config.json_load_options
      end
    end
  end
end
