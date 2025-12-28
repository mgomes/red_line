# frozen_string_literal: true

module RedLine
  class Configuration
    # Redis connection options
    attr_accessor :redis_url
    attr_accessor :redis_host
    attr_accessor :redis_port
    attr_accessor :redis_db
    attr_accessor :redis_password
    attr_accessor :redis_timeout
    attr_accessor :redis_connect_timeout
    attr_accessor :redis_read_timeout
    attr_accessor :redis_ssl
    attr_accessor :redis_ssl_params

    # Connection pooling
    attr_accessor :pool_size
    attr_accessor :pool_timeout

    # Global limiter defaults
    attr_accessor :default_wait_timeout
    attr_accessor :default_lock_timeout
    attr_accessor :default_ttl
    attr_accessor :default_policy

    # Backoff configuration (proc accepting limiter, retry_count -> seconds)
    attr_accessor :backoff

    def initialize
      @redis_host = "localhost"
      @redis_port = 6379
      @redis_db = 0
      @pool_size = 5
      @pool_timeout = 5
      @default_wait_timeout = 5
      @default_lock_timeout = 30
      @default_ttl = 60 * 60 * 24 * 90 # 90 days in seconds
      @default_policy = :raise
      @backoff = ->(limiter, count) { [5 * count + rand(5), 300].min }
    end

    def redis_config
      config = {}

      if redis_url
        config[:url] = redis_url
      else
        config[:host] = redis_host if redis_host
        config[:port] = redis_port if redis_port
      end

      config[:db] = redis_db if redis_db
      config[:password] = redis_password if redis_password
      config[:timeout] = redis_timeout if redis_timeout
      config[:connect_timeout] = redis_connect_timeout if redis_connect_timeout
      config[:read_timeout] = redis_read_timeout if redis_read_timeout
      config[:ssl] = redis_ssl if redis_ssl
      config[:ssl_params] = redis_ssl_params if redis_ssl_params

      config
    end
  end
end
