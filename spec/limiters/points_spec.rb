# frozen_string_literal: true

RSpec.describe RedLine::Limiters::Points, :redis do
  describe "basic usage" do
    let(:limiter) { RedLine.points("test-points", 100, 10, wait_timeout: 0.1) }

    it "allows operations that fit within points" do
      result = limiter.within_limit(estimate: 50) { |handle| :success }
      expect(result).to eq(:success)
    end

    it "deducts estimated points" do
      limiter.within_limit(estimate: 60) { |handle| }

      expect(limiter.available_points).to be_within(5).of(40)
    end

    it "raises OverLimit when not enough points" do
      limiter.within_limit(estimate: 80) { |handle| }

      expect { limiter.within_limit(estimate: 50) { |handle| } }.to raise_error(RedLine::OverLimit) do |error|
        expect(error.limiter_name).to eq("test-points")
        expect(error.limiter_type).to eq("points")
        expect(error.limit).to eq(100)
      end
    end
  end

  describe "points adjustment" do
    let(:limiter) { RedLine.points("test-adjust", 100, 10, wait_timeout: 0) }

    it "adjusts points when actual differs from estimate" do
      limiter.within_limit(estimate: 50) do |handle|
        handle.points_used(30)
      end

      expect(limiter.available_points).to be_within(5).of(70)
    end

    it "handles pessimistic estimates" do
      limiter.within_limit(estimate: 80) do |handle|
        handle.points_used(20)
      end

      expect(limiter.available_points).to be_within(5).of(80)
    end

    it "handles optimistic estimates" do
      limiter.within_limit(estimate: 20) do |handle|
        handle.points_used(50)
      end

      expect(limiter.available_points).to be_within(5).of(50)
    end
  end

  describe "refill behavior" do
    let(:limiter) { RedLine.points("test-refill", 100, 50, wait_timeout: 0.1) }

    it "refills points over time" do
      limiter.within_limit(estimate: 100) { |handle| }

      expect(limiter.available_points).to be_within(5).of(0)

      sleep(1.1)

      expect(limiter.available_points).to be_within(10).of(50)
    end
  end

  describe "#available_points" do
    let(:limiter) { RedLine.points("test-available", 1000, 100) }

    it "returns initial capacity when no usage" do
      expect(limiter.available_points).to eq(1000.0)
    end
  end

  describe "policy: :ignore" do
    let(:limiter) { RedLine.points("test-ignore", 50, 10, wait_timeout: 0, policy: :ignore) }

    it "returns nil instead of raising" do
      limiter.within_limit(estimate: 50) { |handle| }

      result = limiter.within_limit(estimate: 10) { |handle| :should_not_execute }
      expect(result).to be_nil
    end
  end
end
