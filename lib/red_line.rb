# frozen_string_literal: true

require_relative "red_line/version"
require_relative "red_line/errors"
require_relative "red_line/configuration"
require_relative "red_line/connection"
require_relative "red_line/base_limiter"
require_relative "red_line/limiters/unlimited"
require_relative "red_line/limiters/bucket"
require_relative "red_line/limiters/window"
require_relative "red_line/limiters/concurrent"
require_relative "red_line/limiters/leaky_bucket"
require_relative "red_line/limiters/points"

module RedLine
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def reset!
      @configuration = nil
      @connection = nil
    end

    def connection
      @connection ||= Connection.new(configuration)
    end

    # Factory method for concurrent limiter
    # Limits to N concurrent operations at any moment
    #
    # @param name [String] Unique name for this limiter
    # @param limit [Integer] Maximum concurrent operations allowed
    # @param wait_timeout [Float] Seconds to wait for a slot (default: 5)
    # @param lock_timeout [Float] Seconds before a lock can be reclaimed (default: 30)
    # @param policy [Symbol] :raise or :ignore when limit exceeded
    # @return [Limiters::Concurrent]
    def concurrent(name, limit, wait_timeout: nil, lock_timeout: nil, policy: nil)
      Limiters::Concurrent.new(
        name, limit,
        wait_timeout: wait_timeout,
        lock_timeout: lock_timeout,
        policy: policy
      )
    end

    # Factory method for bucket (fixed window) limiter
    # Limits to N operations per time bucket
    #
    # @param name [String] Unique name for this limiter
    # @param limit [Integer] Maximum operations per bucket
    # @param interval [Symbol, Integer] :second, :minute, :hour, :day or seconds
    # @param wait_timeout [Float] Seconds to wait/retry (default: 5)
    # @param policy [Symbol] :raise or :ignore when limit exceeded
    # @param ttl [Integer] Metadata TTL in seconds
    # @return [Limiters::Bucket]
    def bucket(name, limit, interval, wait_timeout: nil, policy: nil, ttl: nil)
      Limiters::Bucket.new(
        name, limit, interval,
        wait_timeout: wait_timeout,
        policy: policy,
        ttl: ttl
      )
    end

    # Factory method for window (sliding window) limiter
    # Limits to N operations per sliding time window
    #
    # @param name [String] Unique name for this limiter
    # @param limit [Integer] Maximum operations per window
    # @param interval [Symbol, Integer] :second, :minute, :hour, :day or seconds
    # @param wait_timeout [Float] Seconds to wait/retry (default: 5)
    # @param policy [Symbol] :raise or :ignore when limit exceeded
    # @param ttl [Integer] Metadata TTL in seconds
    # @return [Limiters::Window]
    def window(name, limit, interval, wait_timeout: nil, policy: nil, ttl: nil)
      Limiters::Window.new(
        name, limit, interval,
        wait_timeout: wait_timeout,
        policy: policy,
        ttl: ttl
      )
    end

    # Factory method for leaky bucket limiter
    # Allows burst up to bucket size, then limits to drip rate
    #
    # @param name [String] Unique name for this limiter
    # @param bucket_size [Integer] Maximum burst capacity
    # @param drain_interval [Symbol, Integer] Time to drain full bucket (:second, :minute, etc or seconds)
    # @param wait_timeout [Float] Seconds to wait for drip (default: 5)
    # @param policy [Symbol] :raise or :ignore when limit exceeded
    # @param ttl [Integer] Metadata TTL in seconds
    # @return [Limiters::LeakyBucket]
    def leaky(name, bucket_size, drain_interval, wait_timeout: nil, policy: nil, ttl: nil)
      Limiters::LeakyBucket.new(
        name, bucket_size, drain_interval,
        wait_timeout: wait_timeout,
        policy: policy,
        ttl: ttl
      )
    end

    # Factory method for points-based limiter
    # Bucket with initial points that refill over time
    #
    # @param name [String] Unique name for this limiter
    # @param bucket_points [Integer] Initial/maximum points
    # @param refill_rate [Float] Points refilled per second
    # @param wait_timeout [Float] Seconds to wait for points (default: 5)
    # @param policy [Symbol] :raise or :ignore when limit exceeded
    # @param ttl [Integer] Metadata TTL in seconds
    # @return [Limiters::Points]
    def points(name, bucket_points, refill_rate, wait_timeout: nil, policy: nil, ttl: nil)
      Limiters::Points.new(
        name, bucket_points, refill_rate,
        wait_timeout: wait_timeout,
        policy: policy,
        ttl: ttl
      )
    end

    # Factory method for unlimited limiter
    # Always executes block - for testing and admin bypass
    #
    # @return [Limiters::Unlimited]
    def unlimited
      Limiters::Unlimited.new
    end
  end
end
