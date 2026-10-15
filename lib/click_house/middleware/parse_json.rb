# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ParseJson < ResponseBase
      Faraday::Response.register_middleware self => self

      # @param env [Faraday::Env]
      def on_complete(env)
        return if error?(env) || !content_type?(env, content_type)

        env.body = JSON.parse(env.body, **config.json_load_options) unless blank_body?(env)
      end
    end
  end
end
