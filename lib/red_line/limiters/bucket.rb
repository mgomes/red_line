# frozen_string_literal: true

module RedLine
  module Limiters
    class Bucket < BaseLimiter
      INTERVALS = {
        second: 1,
        minute: 60,
        hour: 3600,
        day: 86400
      }.freeze

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
          bucket_key = current_bucket_key
          bucket_ttl = bucket_ttl_seconds

          result = connection.call_script(
            "bucket_increment",
            keys: [bucket_key],
            args: [@limit, bucket_ttl]
          )

          current_count, success, remaining_ttl = result

          if success == 1
            return yield
          end

          if @interval_seconds > 1
            return handle_over_limit(current_count, remaining_ttl)
          end

          remaining_wait = deadline - current_time
          if remaining_wait <= 0
            return handle_over_limit(current_count, remaining_ttl)
          end

          sleep_time = [remaining_ttl.to_f, remaining_wait, 1.0].min
          sleep(sleep_time)
        end
      end

      def remaining
        bucket_key = current_bucket_key
        current = connection.call("GET", bucket_key)
        current = current.to_i if current
        [@limit - (current || 0), 0].max
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
          interval.to_i
        else
          raise ArgumentError, "Interval must be a Symbol or Numeric, got #{interval.class}"
        end
      end

      def current_bucket_key
        bucket_timestamp = (current_time / @interval_seconds).floor * @interval_seconds
        redis_key(bucket_timestamp.to_i.to_s)
      end

      def bucket_ttl_seconds
        [@interval_seconds * 2, @ttl].min
      end

      def handle_over_limit(current_count, remaining_ttl)
        case @policy
        when :ignore
          nil
        else
          raise OverLimit.new(
            limiter_name: @name,
            limiter_type: "bucket",
            limit: @limit,
            current: current_count,
            retry_after: remaining_ttl.positive? ? remaining_ttl : nil
          )
        end
      end
    end
  end
end
