# frozen_string_literal: true

require "redis-client"
require "connection_pool"

module RedLine
  class Connection
    LUA_SCRIPTS_PATH = File.expand_path("lua", __dir__)

    def initialize(config = nil)
      @config = config || RedLine.configuration
      @pool = nil
      @script_shas = {}
      @script_contents = {}
      @mutex = Mutex.new
    end

    def pool
      @pool || @mutex.synchronize { @pool ||= create_pool }
    end

    def with(&block)
      pool.with(&block)
    end

    def call(*args)
      with { |conn| conn.call(*args) }
    end

    def blocking_call(timeout, *args)
      with { |conn| conn.blocking_call(timeout, *args) }
    end

    def call_script(name, keys:, args:)
      sha = script_sha(name)
      with do |conn|
        begin
          conn.call("EVALSHA", sha, keys.length, *keys, *args)
        rescue RedisClient::CommandError => e
          if e.message.include?("NOSCRIPT")
            sha = reload_script!(conn, name)
            conn.call("EVALSHA", sha, keys.length, *keys, *args)
          else
            raise
          end
        end
      end
    end

    def flush_scripts!
      @mutex.synchronize do
        @script_shas.clear
      end
    end

    private

    def create_pool
      redis_config = RedisClient.config(**@config.redis_config)
      ConnectionPool.new(size: @config.pool_size, timeout: @config.pool_timeout) do
        redis_config.new_client
      end
    end

    def script_sha(name)
      @script_shas[name] || @mutex.synchronize do
        @script_shas[name] ||= load_script(name)
      end
    end

    def load_script(name)
      script = script_content(name)
      with { |conn| conn.call("SCRIPT", "LOAD", script) }
    end

    def reload_script!(conn, name)
      script = script_content(name)
      sha = conn.call("SCRIPT", "LOAD", script)
      @mutex.synchronize { @script_shas[name] = sha }
      sha
    end

    def script_content(name)
      @script_contents[name] ||= begin
        path = File.join(LUA_SCRIPTS_PATH, "#{name}.lua")
        unless File.exist?(path)
          raise ArgumentError, "Lua script not found: #{name}"
        end
        File.read(path)
      end
    end
  end
end
