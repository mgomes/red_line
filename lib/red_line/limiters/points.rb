# frozen_string_literal: true

module RedLine
  module Limiters
    class Points < BaseLimiter
      class Handle
        def initialize(limiter, estimated_cost)
          @limiter = limiter
          @estimated_cost = estimated_cost
          @adjusted = false
        end

        def points_used(actual)
          return if @adjusted
          @adjusted = true

          if actual != @estimated_cost
            @limiter.send(:adjust_points, @estimated_cost, actual)
          end
        end
      end

      attr_reader :bucket_points, :refill_rate

      def initialize(name, bucket_points, refill_rate, wait_timeout: nil, policy: nil, ttl: nil)
        super(name, bucket_points)
        @bucket_points = bucket_points
        @refill_rate = refill_rate.to_f
        @wait_timeout = wait_timeout || config.default_wait_timeout
        @policy = policy || config.default_policy
        @ttl = ttl || config.default_ttl
      end

      def within_limit(estimate:)
        deadline = current_time + @wait_timeout

        loop do
          result = connection.call_script(
            "points_check",
            keys: [points_key],
            args: [current_time, @bucket_points, @refill_rate, estimate, @ttl]
          )

          available, success, wait_time = result

          if success == 1
            handle = Handle.new(self, estimate)
            return yield(handle)
          end

          remaining_wait = deadline - current_time
          if remaining_wait <= 0
            return handle_over_limit(available, wait_time, estimate)
          end

          sleep_time = [wait_time.to_f, remaining_wait].min
          sleep_time = 0.1 if sleep_time <= 0
          sleep(sleep_time)
        end
      end

      def available_points
        state = connection.call("HGETALL", points_key)
        return @bucket_points.to_f if state.nil? || state.empty?

        stored_points = (state["points"] || @bucket_points.to_s).to_f
        last_refill = (state["last_refill"] || current_time.to_s).to_f

        elapsed = current_time - last_refill
        refilled = elapsed * @refill_rate
        [@bucket_points, stored_points + refilled].min
      end

      def inspect
        "#<#{self.class.name} name=#{@name.inspect} bucket_points=#{@bucket_points} refill_rate=#{@refill_rate}>"
      end

      private

      def adjust_points(estimated, actual)
        connection.call_script(
          "points_adjust",
          keys: [points_key],
          args: [estimated, actual, @bucket_points, @ttl]
        )
      end

      def points_key
        @points_key ||= redis_key
      end

      def handle_over_limit(available, wait_time, estimate)
        case @policy
        when :ignore
          nil
        else
          raise OverLimit.new(
            limiter_name: @name,
            limiter_type: "points",
            limit: @bucket_points,
            current: available.to_i,
            retry_after: wait_time.positive? ? wait_time : nil
          )
        end
      end
    end
  end
end
