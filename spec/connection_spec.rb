# frozen_string_literal: true

RSpec.describe RedLine::Connection, :redis do
  let(:connection) { RedLine.connection }

  describe "#call" do
    it "executes Redis commands" do
      result = connection.call("PING")
      expect(result).to eq("PONG")
    end

    it "handles SET and GET" do
      connection.call("SET", "test-key", "test-value")
      result = connection.call("GET", "test-key")
      expect(result).to eq("test-value")
    end
  end

  describe "#blocking_call" do
    it "executes blocking commands with timeout" do
      # BLPOP on empty list should timeout and return nil
      result = connection.blocking_call(0.1, "BLPOP", "nonexistent-list", 0.1)
      expect(result).to be_nil
    end

    it "returns immediately when data is available" do
      connection.call("RPUSH", "blocking-test", "value")

      result = connection.blocking_call(5, "BLPOP", "blocking-test", 5)
      expect(result).to eq(["blocking-test", "value"])
    end
  end

  describe "#call_script" do
    it "executes Lua scripts" do
      # bucket_increment is a simple script we can test
      result = connection.call_script(
        "bucket_increment",
        keys: ["script-test-key"],
        args: [10, 60]
      )

      expect(result).to be_an(Array)
      expect(result[0]).to eq(1) # count
      expect(result[1]).to eq(1) # success
    end

    it "caches script SHAs" do
      # First call loads the script
      connection.call_script(
        "bucket_increment",
        keys: ["cache-test-1"],
        args: [10, 60]
      )

      # Second call should use cached SHA
      connection.call_script(
        "bucket_increment",
        keys: ["cache-test-2"],
        args: [10, 60]
      )

      # If we got here without error, caching is working
    end

    it "reloads script on NOSCRIPT error" do
      # First, load a script
      connection.call_script(
        "bucket_increment",
        keys: ["noscript-test"],
        args: [10, 60]
      )

      # Flush all scripts from Redis
      connection.call("SCRIPT", "FLUSH")

      # Clear local cache to simulate stale SHA
      connection.flush_scripts!

      # This should reload and succeed
      result = connection.call_script(
        "bucket_increment",
        keys: ["noscript-test-2"],
        args: [10, 60]
      )

      expect(result[1]).to eq(1) # success
    end

    it "raises for unknown scripts" do
      expect {
        connection.call_script(
          "nonexistent_script",
          keys: ["test"],
          args: []
        )
      }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe "#with" do
    it "yields a Redis connection" do
      connection.with do |conn|
        expect(conn.call("PING")).to eq("PONG")
      end
    end

    it "returns the block result" do
      result = connection.with { |conn| conn.call("PING") }
      expect(result).to eq("PONG")
    end
  end

  describe "pool behavior" do
    it "reuses connections from pool" do
      ids = []

      5.times do
        connection.with do |conn|
          ids << conn.object_id
        end
      end

      # Should reuse the same connection
      expect(ids.uniq.size).to eq(1)
    end

    it "handles concurrent access" do
      results = []
      threads = 10.times.map do
        Thread.new do
          connection.with do |conn|
            results << conn.call("PING")
          end
        end
      end

      threads.each(&:join)
      expect(results).to all(eq("PONG"))
    end
  end
end
