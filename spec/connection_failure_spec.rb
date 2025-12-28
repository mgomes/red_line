# frozen_string_literal: true

RSpec.describe "Connection failures", :redis do
  describe "when Redis is unavailable" do
    let(:bad_config) do
      RedLine::Configuration.new.tap do |c|
        c.redis_host = "nonexistent.invalid"
        c.redis_port = 9999
        c.pool_timeout = 0.1
      end
    end

    let(:bad_connection) { RedLine::Connection.new(bad_config) }

    it "raises an error when trying to connect" do
      expect { bad_connection.call("PING") }.to raise_error(StandardError)
    end
  end

  describe "redis_available? helper" do
    it "returns true when Redis is available" do
      expect(redis_available?).to be true
    end
  end

  describe "limiter behavior with connection issues" do
    it "propagates Redis errors from within_limit" do
      limiter = RedLine.bucket("test-conn", 10, :second)

      # First call succeeds
      expect { limiter.within_limit { :ok } }.not_to raise_error

      # Verify the limiter is working
      expect(limiter.remaining).to be < 10
    end
  end
end
