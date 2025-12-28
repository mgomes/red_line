# frozen_string_literal: true

module RedLine
  class Error < StandardError; end

  class OverLimit < Error
    attr_reader :limiter_name, :limiter_type, :limit, :current, :retry_after

    def initialize(message = nil, limiter_name:, limiter_type:, limit:, current:, retry_after: nil)
      @limiter_name = limiter_name
      @limiter_type = limiter_type
      @limit = limit
      @current = current
      @retry_after = retry_after
      super(message || default_message)
    end

    private

    def default_message
      msg = "Rate limit exceeded for #{limiter_type} limiter '#{limiter_name}': #{current}/#{limit}"
      msg += ", retry after #{retry_after}s" if retry_after
      msg
    end
  end

  class InvalidName < Error
    attr_reader :name

    VALID_PATTERN = /\A[a-zA-Z0-9_-]+\z/

    def initialize(name)
      @name = name
      super("Invalid limiter name '#{name}': must contain only letters, numbers, hyphens, and underscores")
    end
  end

  class ConnectionError < Error
    attr_reader :original_error

    def initialize(message, original_error: nil)
      @original_error = original_error
      super(message)
    end
  end

  class LockLost < Error
    attr_reader :limiter_name, :lock_id

    def initialize(limiter_name:, lock_id:)
      @limiter_name = limiter_name
      @lock_id = lock_id
      super("Lock lost for concurrent limiter '#{limiter_name}' (lock_id: #{lock_id})")
    end
  end
end
