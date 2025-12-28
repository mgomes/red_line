# frozen_string_literal: true

require "securerandom"

module RedLine
  module Limiters
    class Concurrent < BaseLimiter
      attr_reader :wait_timeout, :lock_timeout

      def initialize(name, limit, wait_timeout: nil, lock_timeout: nil, policy: nil)
        super(name, limit)
        @wait_timeout = wait_timeout || config.default_wait_timeout
        @lock_timeout = lock_timeout || config.default_lock_timeout
        @policy = policy || config.default_policy
        @ttl = config.default_ttl
      end

      def within_limit
        reclaim_expired_locks
        initialize_slots

        lock_id = acquire_lock

        unless lock_id
          return handle_over_limit
        end

        start_time = current_time
        begin
          result = yield
          record_held_time(current_time - start_time)
          result
        rescue => e
          check_for_overage(start_time)
          raise
        ensure
          release_lock(lock_id)
        end
      end

      def held
        connection.call("HLEN", locks_key).to_i
      end

      def metrics
        result = connection.call("HGETALL", metrics_key)
        return {} if result.nil? || result.empty?
        result.transform_values { |v| v.to_s.include?('.') ? v.to_f : v.to_i }
      end

      def inspect
        "#<#{self.class.name} name=#{@name.inspect} limit=#{@limit} lock_timeout=#{@lock_timeout}>"
      end

      private

      def acquire_lock
        lock_id = generate_lock_id

        slot = connection.call("LPOP", slots_key)
        if slot
          record_lock(lock_id)
          increment_metric(:immediate)
          increment_metric(:held)
          return lock_id
        end

        increment_metric(:waited)
        wait_start = current_time

        result = connection.blocking_call(@wait_timeout, "BLPOP", slots_key, @wait_timeout)

        if result
          record_lock(lock_id)
          record_wait_time(current_time - wait_start)
          increment_metric(:held)
          return lock_id
        end

        nil
      end

      def release_lock(lock_id)
        connection.call_script(
          "concurrent_release",
          keys: [slots_key, locks_key],
          args: [lock_id, @ttl]
        )
      end

      def reclaim_expired_locks
        connection.call_script(
          "concurrent_reclaim",
          keys: [slots_key, locks_key, metrics_key],
          args: [current_time, @lock_timeout, @ttl]
        )
      end

      def initialize_slots
        connection.call_script(
          "concurrent_init",
          keys: [slots_key, locks_key],
          args: [@limit, @ttl]
        )
      end

      def record_lock(lock_id)
        connection.call("HSET", locks_key, lock_id, current_time.to_s)
        connection.call("EXPIRE", locks_key, @ttl)
      end

      def generate_lock_id
        "#{Process.pid}:#{Thread.current.object_id}:#{SecureRandom.hex(8)}"
      end

      def slots_key
        @slots_key ||= redis_key("slots")
      end

      def locks_key
        @locks_key ||= redis_key("locks")
      end

      def metrics_key
        @metrics_key ||= redis_key("metrics")
      end

      def increment_metric(name)
        connection.call("HINCRBY", metrics_key, name.to_s, 1)
        connection.call("EXPIRE", metrics_key, @ttl)
      end

      def record_held_time(seconds)
        connection.call("HINCRBYFLOAT", metrics_key, "held_time", seconds)
        connection.call("EXPIRE", metrics_key, @ttl)
      end

      def record_wait_time(seconds)
        connection.call("HINCRBYFLOAT", metrics_key, "wait_time", seconds)
        connection.call("EXPIRE", metrics_key, @ttl)
      end

      def check_for_overage(start_time)
        elapsed = current_time - start_time
        if elapsed > @lock_timeout
          increment_metric(:overages)
        end
      end

      def handle_over_limit
        case @policy
        when :ignore
          nil
        else
          raise OverLimit.new(
            limiter_name: @name,
            limiter_type: "concurrent",
            limit: @limit,
            current: held,
            retry_after: nil
          )
        end
      end
    end
  end
end
