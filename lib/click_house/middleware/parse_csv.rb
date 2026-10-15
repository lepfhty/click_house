# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ParseCsv < ResponseBase
      Faraday::Response.register_middleware self => self

      # @param env [Faraday::Env]
      def on_complete(env)
        return if error?(env) || !content_type?(env, content_type)

        env.body = blank_body?(env) ? nil : CSV.parse(env.body)
      end
    end
  end
end
