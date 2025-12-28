# frozen_string_literal: true

require "securerandom"

module RedLine
  module Limiters
    class Window < BaseLimiter
      INTERVALS = {
        second: 1,
        minute: 60,
        hour: 3600,
        day: 86400
      }.freeze

      SLEEP_INTERVAL = 0.5

      attr_reader :interval, :interval_seconds

      def initialize(name, limit, interval, wait_timeout: nil, policy: nil, ttl: nil)
        super(name, limit)
        @interval = interval
        @interval_seconds = resolve_interval(interval)
        @wait_timeout = wait_timeout || config.default_wait_timeout
        @policy = policy || config.default_policy
        @ttl = ttl || config.default_ttl
      end

      def within_limit
        deadline = current_time + @wait_timeout

        loop do
          unique_id = SecureRandom.uuid
          window_ttl = [@interval_seconds * 2, @ttl].min

          result = connection.call_script(
            "window_check",
            keys: [window_key],
            args: [current_time, @interval_seconds, @limit, unique_id, window_ttl]
          )

          count, success, wait_time = result

          if success == 1
            return yield
          end

          remaining_wait = deadline - current_time
          if remaining_wait <= 0
            return handle_over_limit(count, wait_time)
          end

          sleep_time = [SLEEP_INTERVAL, remaining_wait, wait_time.to_f].min
          sleep_time = SLEEP_INTERVAL if sleep_time <= 0
          sleep(sleep_time)
        end
      end

      def remaining
        window_start = current_time - @interval_seconds
        connection.call("ZREMRANGEBYSCORE", window_key, "-inf", window_start)
        count = connection.call("ZCARD", window_key)
        [@limit - count.to_i, 0].max
      end

      def inspect
        "#<#{self.class.name} name=#{@name.inspect} limit=#{@limit} interval=#{@interval.inspect}>"
      end

      private

      def resolve_interval(interval)
        case interval
        when Symbol
          INTERVALS.fetch(interval) do
            raise ArgumentError, "Unknown interval: #{interval}. Valid intervals: #{INTERVALS.keys.join(', ')}"
          end
        when Numeric
          interval.to_f
        else
          raise ArgumentError, "Interval must be a Symbol or Numeric, got #{interval.class}"
        end
      end

      def window_key
        @window_key ||= redis_key
      end

      def handle_over_limit(current_count, wait_time)
        case @policy
        when :ignore
          nil
        else
          raise OverLimit.new(
            limiter_name: @name,
            limiter_type: "window",
            limit: @limit,
            current: current_count,
            retry_after: wait_time.positive? ? wait_time : nil
          )
        end
      end
    end
  end
end
