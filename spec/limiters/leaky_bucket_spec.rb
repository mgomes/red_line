# frozen_string_literal: true

RSpec.describe RedLine::Limiters::LeakyBucket, :redis do
  describe "burst behavior" do
    # Use slow drain rate (0.1/sec) so bucket fills before draining
    let(:limiter) { RedLine.leaky("test-leaky", 5, 50, wait_timeout: 0.1) }

    it "allows burst up to bucket size" do
      results = []
      5.times { results << limiter.within_limit { :ok } }
      expect(results).to all(eq(:ok))
    end

    it "raises OverLimit when bucket is full" do
      5.times { limiter.within_limit { } }

      expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit) do |error|
        expect(error.limiter_name).to eq("test-leaky")
        expect(error.limiter_type).to eq("leaky_bucket")
        expect(error.limit).to eq(5)
      end
    end
  end

  describe "drip behavior" do
    # drain_rate = 2/1 = 2 per second, so bucket drains quickly
    let(:limiter) { RedLine.leaky("test-drip", 2, 1, wait_timeout: 0.1) }

    it "allows requests as bucket drains" do
      2.times { limiter.within_limit { } }

      # Bucket should be at ~2, but drains at 2/sec, so wait 0.6s and level should be ~0.8
      sleep(0.6)

      # Now bucket has room again
      expect { limiter.within_limit { } }.not_to raise_error
    end
  end

  describe "with :minute interval" do
    let(:limiter) { RedLine.leaky("test-minute", 60, :minute, wait_timeout: 0) }

    it "drains at 1 per second rate" do
      expect(limiter.drain_rate).to eq(1.0)
    end
  end

  describe "#level" do
    let(:limiter) { RedLine.leaky("test-level", 10, 10, wait_timeout: 0) }

    it "returns current bucket level" do
      expect(limiter.level).to eq(0.0)

      3.times { limiter.within_limit { } }
      expect(limiter.level).to be_within(0.5).of(3.0)
    end

    it "decreases over time" do
      5.times { limiter.within_limit { } }

      sleep(1.1)

      expect(limiter.level).to be < 5.0
    end
  end

  describe "policy: :ignore" do
    # Slow drain so bucket fills
    let(:limiter) { RedLine.leaky("test-ignore", 2, 20, wait_timeout: 0, policy: :ignore) }

    it "returns nil instead of raising" do
      2.times { limiter.within_limit { } }

      result = limiter.within_limit { :should_not_execute }
      expect(result).to be_nil
    end
  end
end
