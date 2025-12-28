# frozen_string_literal: true

RSpec.describe RedLine::Limiters::Unlimited do
  let(:limiter) { described_class.new }

  describe "#within_limit" do
    it "always executes the block" do
      result = limiter.within_limit { :success }
      expect(result).to eq(:success)
    end

    it "never raises OverLimit" do
      1000.times do
        expect { limiter.within_limit { } }.not_to raise_error
      end
    end
  end

  describe "#inspect" do
    it "returns a readable representation" do
      expect(limiter.inspect).to eq("#<RedLine::Limiters::Unlimited>")
    end
  end
end
