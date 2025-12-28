# frozen_string_literal: true

RSpec.describe RedLine::Limiters::Bucket, :redis do
  describe "with :second interval" do
    let(:limiter) { RedLine.bucket("test-bucket", 5, :second, wait_timeout: 0.1) }

    it "allows operations up to the limit" do
      results = []
      5.times { results << limiter.within_limit { :ok } }
      expect(results).to all(eq(:ok))
    end

    it "raises OverLimit when limit exceeded" do
      5.times { limiter.within_limit { } }

      expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit) do |error|
        expect(error.limiter_name).to eq("test-bucket")
        expect(error.limiter_type).to eq("bucket")
        expect(error.limit).to eq(5)
      end
    end

    it "resets after the bucket expires" do
      5.times { limiter.within_limit { } }

      sleep(1.1)

      expect { limiter.within_limit { :ok } }.not_to raise_error
    end
  end

  describe "with :minute interval" do
    let(:limiter) { RedLine.bucket("test-minute", 3, :minute, wait_timeout: 0) }

    it "raises immediately when over limit" do
      3.times { limiter.within_limit { } }

      start = Time.now
      expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit)
      elapsed = Time.now - start

      expect(elapsed).to be < 0.1
    end
  end

  describe "with custom interval" do
    let(:limiter) { RedLine.bucket("test-custom", 2, 2, wait_timeout: 0) }

    it "uses custom seconds as interval" do
      expect(limiter.interval_seconds).to eq(2)
    end
  end

  describe "#remaining" do
    let(:limiter) { RedLine.bucket("test-remaining", 10, :second) }

    it "returns remaining capacity" do
      expect(limiter.remaining).to eq(10)

      3.times { limiter.within_limit { } }
      expect(limiter.remaining).to eq(7)
    end
  end

  describe "policy: :ignore" do
    let(:limiter) { RedLine.bucket("test-ignore", 2, :second, wait_timeout: 0, policy: :ignore) }

    it "returns nil instead of raising" do
      2.times { limiter.within_limit { } }

      result = limiter.within_limit { :should_not_execute }
      expect(result).to be_nil
    end
  end

  describe "invalid interval" do
    it "raises ArgumentError for unknown symbol" do
      expect { RedLine.bucket("test", 5, :invalid) }.to raise_error(ArgumentError, /Unknown interval/)
    end
  end
end
