# frozen_string_literal: true

module ClickHouse
  module Middleware
    class ParseJsonOj < ResponseBase
      Faraday::Response.register_middleware self => self

      # @param env [Faraday::Env]
      def on_complete(env)
        return if error?(env) || !content_type?(env, content_type)

        env.body = Oj.load(env.body, config.oj_load_options) unless blank_body?(env)
      end

      private

      def on_setup
        require 'oj' unless defined?(Oj)
      end
    end
  end
end
