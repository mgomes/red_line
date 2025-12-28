# frozen_string_literal: true

RSpec.describe "Edge cases", :redis do
  describe "zero and small limits" do
    describe "bucket with limit of 1" do
      let(:limiter) { RedLine.bucket("edge-one", 1, 60, wait_timeout: 0) }

      it "allows exactly one operation" do
        expect { limiter.within_limit { :ok } }.not_to raise_error
        expect { limiter.within_limit { :ok } }.to raise_error(RedLine::OverLimit)
      end
    end

    describe "concurrent with limit of 1" do
      let(:limiter) { RedLine.concurrent("edge-mutex", 1, wait_timeout: 0.1) }

      it "acts as a distributed mutex" do
        results = []
        mutex = Mutex.new

        thread = Thread.new do
          limiter.within_limit do
            mutex.synchronize { results << :first }
            sleep 0.3
          end
        end

        sleep 0.1 # Let first thread acquire

        expect { limiter.within_limit { results << :second } }.to raise_error(RedLine::OverLimit)

        thread.join
        expect(results).to eq([:first])
      end
    end

    describe "window with limit of 1" do
      let(:limiter) { RedLine.window("edge-window", 1, 60, wait_timeout: 0) }

      it "allows exactly one operation per window" do
        expect { limiter.within_limit { :ok } }.not_to raise_error
        expect { limiter.within_limit { :ok } }.to raise_error(RedLine::OverLimit)
      end
    end

    describe "leaky bucket with size of 1" do
      let(:limiter) { RedLine.leaky("edge-leaky", 1, 60, wait_timeout: 0) }

      it "allows one burst then blocks" do
        expect { limiter.within_limit { :ok } }.not_to raise_error
        expect { limiter.within_limit { :ok } }.to raise_error(RedLine::OverLimit)
      end
    end

    describe "points with small capacity" do
      let(:limiter) { RedLine.points("edge-points", 10, 1, wait_timeout: 0) }

      it "rejects requests exceeding capacity" do
        expect { limiter.within_limit(estimate: 15) { :ok } }.to raise_error(RedLine::OverLimit)
      end

      it "allows requests within capacity" do
        expect { limiter.within_limit(estimate: 10) { :ok } }.not_to raise_error
      end
    end
  end

  describe "timeout edge cases" do
    describe "wait_timeout of 0" do
      let(:limiter) { RedLine.bucket("edge-zero-timeout", 1, 60, wait_timeout: 0) }

      it "fails immediately when limit exceeded" do
        limiter.within_limit { }

        start = Time.now
        expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit)
        elapsed = Time.now - start

        expect(elapsed).to be < 0.1
      end
    end

    describe "very short wait_timeout" do
      # Use a longer interval (60s) so the bucket doesn't reset during the test
      let(:limiter) { RedLine.bucket("edge-short-timeout", 1, 60, wait_timeout: 0.05) }

      it "respects the short timeout" do
        limiter.within_limit { }

        start = Time.now
        expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit)
        elapsed = Time.now - start

        # Should fail quickly (within wait_timeout) not wait for bucket reset
        expect(elapsed).to be < 0.2
      end
    end
  end

  describe "limiter reuse" do
    let(:limiter) { RedLine.bucket("edge-reuse", 100, 60, wait_timeout: 0) }

    it "tracks state across multiple calls" do
      10.times { limiter.within_limit { } }
      expect(limiter.remaining).to eq(90)

      10.times { limiter.within_limit { } }
      expect(limiter.remaining).to eq(80)
    end

    it "can be used from multiple threads" do
      results = []
      threads = 10.times.map do
        Thread.new do
          5.times do
            limiter.within_limit { results << Thread.current.object_id }
          end
        end
      end

      threads.each(&:join)
      expect(results.size).to eq(50)
      expect(limiter.remaining).to eq(50)
    end
  end

  describe "large limits" do
    let(:limiter) { RedLine.bucket("edge-large", 1_000_000, 60, wait_timeout: 0) }

    it "handles large limits" do
      1000.times { limiter.within_limit { } }
      expect(limiter.remaining).to eq(999_000)
    end
  end

  describe "block return values" do
    let(:limiter) { RedLine.bucket("edge-return", 10, 60) }

    it "returns the block result" do
      result = limiter.within_limit { { status: "ok", data: [1, 2, 3] } }
      expect(result).to eq({ status: "ok", data: [1, 2, 3] })
    end

    it "returns nil from block" do
      result = limiter.within_limit { nil }
      expect(result).to be_nil
    end

    it "returns false from block" do
      result = limiter.within_limit { false }
      expect(result).to be false
    end
  end

  describe "exception handling in blocks" do
    let(:limiter) { RedLine.concurrent("edge-exception", 2, wait_timeout: 1) }

    it "releases lock when block raises" do
      expect(limiter.held).to eq(0)

      expect {
        limiter.within_limit { raise "boom" }
      }.to raise_error(RuntimeError, "boom")

      expect(limiter.held).to eq(0)
    end

    it "releases lock when block raises custom exception" do
      custom_error = Class.new(StandardError)

      expect {
        limiter.within_limit { raise custom_error, "custom" }
      }.to raise_error(custom_error)

      expect(limiter.held).to eq(0)
    end
  end
end
