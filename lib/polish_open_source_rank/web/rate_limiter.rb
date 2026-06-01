# frozen_string_literal: true

module PolishOpenSourceRank
  module Web
    class RateLimiter
      Rule = Struct.new(:name, :limit, :window, keyword_init: true)
      Response = Struct.new(:allowed?, :rule, :remaining, :reset_at, keyword_init: true)

      RULES = {
        %r{\A/(auth/|logout\z)} => Rule.new(name: 'auth', limit: 30, window: 60),
        %r{\A/badges/} => Rule.new(name: 'badges', limit: 240, window: 60),
        %r{\A/internal/} => Rule.new(name: 'internal', limit: 120, window: 60),
        %r{\A/(latest|\d{4}-\d{2})/(locations/[^/]+/)?(users|repositories|organizations|organization-repositories)/} =>
          Rule.new(name: 'ranking-detail', limit: 600, window: 60)
      }.freeze

      class Store
        def initialize(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
          @clock = clock
          @buckets = {}
          @mutex = Mutex.new
        end

        def check(key, rule)
          now = clock.call
          mutex.synchronize do
            bucket = bucket_for(key, rule, now)
            bucket[:count] += 1

            Response.new(
              allowed?: bucket.fetch(:count) <= rule.limit,
              rule: rule,
              remaining: [rule.limit - bucket.fetch(:count), 0].max,
              reset_at: bucket.fetch(:reset_at)
            )
          end
        end

        def reset
          mutex.synchronize { buckets.clear }
        end

        private

        attr_reader :buckets, :clock, :mutex

        def bucket_for(key, rule, now)
          bucket = buckets[key]
          return bucket if bucket && bucket.fetch(:reset_at) > now

          buckets[key] = { count: 0, reset_at: now + rule.window }
        end
      end

      def self.store
        @store ||= Store.new
      end

      def self.reset!
        store.reset
      end

      def initialize(app, store: self.class.store, rules: RULES)
        @app = app
        @store = store
        @rules = rules
      end

      def call(env)
        rule = rule_for(env.fetch('PATH_INFO', ''))
        return app.call(env) unless rule

        result = store.check(rate_limit_key(env, rule), rule)
        return app.call(env) if result.allowed?

        rate_limited_response(result)
      end

      private

      attr_reader :app, :rules, :store

      def rule_for(path)
        rules.each do |pattern, rule|
          return rule if path.match?(pattern)
        end
        nil
      end

      def rate_limit_key(env, rule)
        "#{rule.name}:#{client_ip(env)}"
      end

      def client_ip(env)
        forwarded_for = env['HTTP_X_FORWARDED_FOR'].to_s.split(',').first.to_s.strip
        return forwarded_for unless forwarded_for.empty?

        env.fetch('REMOTE_ADDR', 'unknown')
      end

      def rate_limited_response(result)
        retry_after = [result.reset_at - Process.clock_gettime(Process::CLOCK_MONOTONIC), 1].max.ceil
        [
          429,
          {
            'Content-Type' => 'text/plain',
            'Cache-Control' => 'no-store',
            'Retry-After' => retry_after.to_s,
            'RateLimit-Limit' => result.rule.limit.to_s,
            'RateLimit-Remaining' => result.remaining.to_s
          },
          ["Too many requests\n"]
        ]
      end
    end
  end
end
