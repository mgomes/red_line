# frozen_string_literal: true

module RedLine
  class BaseLimiter
    attr_reader :name, :limit

    def initialize(name, limit)
      validate_name!(name) if name
      @name = name
      @limit = limit
    end

    def within_limit(&block)
      raise NotImplementedError, "Subclasses must implement #within_limit"
    end

    def inspect
      "#<#{self.class.name} name=#{@name.inspect} limit=#{@limit}>"
    end

    protected

    def config
      RedLine.configuration
    end

    def connection
      RedLine.connection
    end

    def validate_name!(name)
      unless name.is_a?(String) && name.match?(InvalidName::VALID_PATTERN)
        raise InvalidName.new(name)
      end
    end

    def redis_key(*suffixes)
      parts = ["redline", limiter_type, @name]
      parts.concat(suffixes) unless suffixes.empty?
      parts.join(":")
    end

    def limiter_type
      self.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end

    def current_time
      Process.clock_gettime(Process::CLOCK_REALTIME)
    end
  end
end
