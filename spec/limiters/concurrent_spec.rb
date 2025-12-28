# frozen_string_literal: true

RSpec.describe RedLine::Limiters::Concurrent, :redis do
  let(:limiter) { RedLine.concurrent("test-concurrent", 2, wait_timeout: 1, lock_timeout: 5) }

  describe "#within_limit" do
    it "allows concurrent operations up to the limit" do
      results = []
      mutex = Mutex.new

      threads = 2.times.map do |i|
        Thread.new do
          limiter.within_limit do
            mutex.synchronize { results << i }
            sleep 0.2
          end
        end
      end

      threads.each(&:join)
      expect(results.size).to eq(2)
    end

    it "blocks and waits for a slot" do
      slot_acquired = false
      blocking_thread = Thread.new do
        limiter.within_limit do
          slot_acquired = true
          sleep 0.5
        end
      end

      sleep 0.1
      expect(slot_acquired).to be true

      waiter_thread = Thread.new do
        limiter.within_limit { :got_it }
      end

      result = waiter_thread.value
      blocking_thread.join

      expect(result).to eq(:got_it)
    end

    it "raises OverLimit when wait_timeout exceeded" do
      threads = 2.times.map do
        Thread.new do
          limiter.within_limit { sleep 2 }
        end
      end

      sleep 0.1

      expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit) do |error|
        expect(error.limiter_name).to eq("test-concurrent")
        expect(error.limiter_type).to eq("concurrent")
        expect(error.limit).to eq(2)
      end

      threads.each(&:kill)
    end

    it "releases the lock when block completes" do
      limiter.within_limit { :done }
      expect(limiter.held).to eq(0)
    end

    it "releases the lock when block raises" do
      expect {
        limiter.within_limit { raise "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(limiter.held).to eq(0)
    end
  end

  describe "#held" do
    it "returns the number of currently held locks" do
      expect(limiter.held).to eq(0)

      thread = Thread.new do
        limiter.within_limit { sleep 1 }
      end

      sleep 0.1
      expect(limiter.held).to eq(1)

      thread.kill
      thread.join
    end
  end

  describe "#metrics" do
    it "tracks held count" do
      limiter.within_limit { }
      expect(limiter.metrics["held"]).to eq(1)
    end

    it "tracks immediate acquisitions" do
      limiter.within_limit { }
      expect(limiter.metrics["immediate"]).to eq(1)
    end
  end

  describe "lock reclamation" do
    let(:limiter) { RedLine.concurrent("test-reclaim", 1, wait_timeout: 0.5, lock_timeout: 0.5) }

    it "reclaims expired locks" do
      RedLine.connection.call("HSET", "redline:concurrent:test-reclaim:locks", "old-lock", (Time.now.to_f - 10).to_s)
      RedLine.connection.call("LPOP", "redline:concurrent:test-reclaim:slots")

      expect { limiter.within_limit { :success } }.not_to raise_error
    end
  end

  describe "policy: :ignore" do
    let(:limiter) { RedLine.concurrent("test-ignore", 1, wait_timeout: 0.1, policy: :ignore) }

    it "returns nil instead of raising" do
      thread = Thread.new { limiter.within_limit { sleep 1 } }
      sleep 0.1

      result = limiter.within_limit { :should_not_execute }
      expect(result).to be_nil

      thread.kill
      thread.join
    end
  end
end
