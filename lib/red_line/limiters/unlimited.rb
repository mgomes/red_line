# frozen_string_literal: true

module RedLine
  module Limiters
    class Unlimited < BaseLimiter
      def initialize
        super(nil, nil)
      end

      def within_limit
        yield
      end

      def inspect
        "#<#{self.class.name}>"
      end
    end
  end
end
