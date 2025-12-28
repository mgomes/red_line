# frozen_string_literal: true

RSpec.describe RedLine::Limiters::Window, :redis do
  describe "with :second interval" do
    let(:limiter) { RedLine.window("test-window", 5, :second, wait_timeout: 0.1) }

    it "allows operations up to the limit" do
      results = []
      5.times { results << limiter.within_limit { :ok } }
      expect(results).to all(eq(:ok))
    end

    it "raises OverLimit when limit exceeded" do
      5.times { limiter.within_limit { } }

      expect { limiter.within_limit { } }.to raise_error(RedLine::OverLimit) do |error|
        expect(error.limiter_name).to eq("test-window")
        expect(error.limiter_type).to eq("window")
        expect(error.limit).to eq(5)
      end
    end

    it "slides the window over time" do
      5.times { limiter.within_limit { } }

      sleep(1.1)

      expect { limiter.within_limit { :ok } }.not_to raise_error
    end
  end

  describe "with custom seconds interval" do
    let(:limiter) { RedLine.window("test-custom", 3, 0.5, wait_timeout: 0.1) }

    it "uses custom seconds" do
      expect(limiter.interval_seconds).to eq(0.5)
    end

    it "allows requests after window slides" do
      3.times { limiter.within_limit { } }

      sleep(0.6)

      expect { limiter.within_limit { } }.not_to raise_error
    end
  end

  describe "#remaining" do
    let(:limiter) { RedLine.window("test-remaining", 10, :second) }

    it "returns remaining capacity" do
      expect(limiter.remaining).to eq(10)

      3.times { limiter.within_limit { } }
      expect(limiter.remaining).to eq(7)
    end
  end

  describe "policy: :ignore" do
    let(:limiter) { RedLine.window("test-ignore", 2, :second, wait_timeout: 0, policy: :ignore) }

    it "returns nil instead of raising" do
      2.times { limiter.within_limit { } }

      result = limiter.within_limit { :should_not_execute }
      expect(result).to be_nil
    end
  end
end
