# frozen_string_literal: true

module RedLine
  module Limiters
    class LeakyBucket < BaseLimiter
      INTERVALS = {
        second: 1,
        minute: 60,
        hour: 3600,
        day: 86400
      }.freeze

      attr_reader :bucket_size, :drain_interval, :drain_rate

      def initialize(name, bucket_size, drain_interval, wait_timeout: nil, policy: nil, ttl: nil)
        super(name, bucket_size)
        @bucket_size = bucket_size
        @drain_interval = drain_interval
        @drain_interval_seconds = resolve_interval(drain_interval)
        @drain_rate = bucket_size.to_f / @drain_interval_seconds
        @wait_timeout = wait_timeout || config.default_wait_timeout
        @policy = policy || config.default_policy
        @ttl = ttl || config.default_ttl
      end

      def within_limit
        deadline = current_time + @wait_timeout

        loop do
          result = connection.call_script(
            "leaky_bucket",
            keys: [bucket_key],
            args: [current_time, @bucket_size, @drain_rate, @ttl]
          )

          level, success, wait_time = result

          if success == 1
            increment_metric(:hits)
            return yield
          end

          remaining_wait = deadline - current_time
          if remaining_wait <= 0
            increment_metric(:misses)
            return handle_over_limit(level, wait_time)
          end

          sleep_time = [wait_time.to_f, remaining_wait, drip_interval].min
          sleep_time = drip_interval if sleep_time <= 0
          increment_metric(:sleep_time, sleep_time)
          sleep(sleep_time)
        end
      end

      def level
        state = connection.call("HGETALL", bucket_key)
        return 0.0 if state.nil? || state.empty?

        stored_level = (state["level"] || "0").to_f
        last_drip = (state["last_drip"] || current_time.to_s).to_f

        elapsed = current_time - last_drip
        drained = elapsed * @drain_rate
        [stored_level - drained, 0].max
      end

      def inspect
        "#<#{self.class.name} name=#{@name.inspect} bucket_size=#{@bucket_size} drain_interval=#{@drain_interval.inspect}>"
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

      def drip_interval
        1.0 / @drain_rate
      end

      def bucket_key
        @bucket_key ||= redis_key
      end

      def metrics_key
        @metrics_key ||= redis_key("metrics")
      end

      def increment_metric(name, value = 1)
        if value.is_a?(Float)
          connection.call("HINCRBYFLOAT", metrics_key, name.to_s, value)
        else
          connection.call("HINCRBY", metrics_key, name.to_s, value)
        end
        connection.call("EXPIRE", metrics_key, @ttl)
      end

      def handle_over_limit(level, wait_time)
        case @policy
        when :ignore
          nil
        else
          raise OverLimit.new(
            limiter_name: @name,
            limiter_type: "leaky_bucket",
            limit: @bucket_size,
            current: level.to_i,
            retry_after: wait_time.positive? ? wait_time : nil
          )
        end
      end
    end
  end
end
