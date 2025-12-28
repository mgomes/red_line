# frozen_string_literal: true

RSpec.describe RedLine do
  it "has a version number" do
    expect(RedLine::VERSION).not_to be_nil
  end

  describe ".configure" do
    after { RedLine.reset! }

    it "yields configuration" do
      RedLine.configure do |config|
        config.redis_host = "custom-host"
        config.pool_size = 20
      end

      expect(RedLine.configuration.redis_host).to eq("custom-host")
      expect(RedLine.configuration.pool_size).to eq(20)
    end
  end

  describe ".connection" do
    it "returns a Connection instance" do
      expect(RedLine.connection).to be_a(RedLine::Connection)
    end

    it "memoizes the connection" do
      conn1 = RedLine.connection
      conn2 = RedLine.connection
      expect(conn1).to equal(conn2)
    end
  end

  describe "factory methods" do
    describe ".concurrent" do
      it "creates a Concurrent limiter" do
        limiter = RedLine.concurrent("test", 5)
        expect(limiter).to be_a(RedLine::Limiters::Concurrent)
        expect(limiter.name).to eq("test")
        expect(limiter.limit).to eq(5)
      end
    end

    describe ".bucket" do
      it "creates a Bucket limiter" do
        limiter = RedLine.bucket("test", 10, :second)
        expect(limiter).to be_a(RedLine::Limiters::Bucket)
        expect(limiter.limit).to eq(10)
        expect(limiter.interval).to eq(:second)
      end
    end

    describe ".window" do
      it "creates a Window limiter" do
        limiter = RedLine.window("test", 10, :minute)
        expect(limiter).to be_a(RedLine::Limiters::Window)
        expect(limiter.limit).to eq(10)
        expect(limiter.interval).to eq(:minute)
      end
    end

    describe ".leaky" do
      it "creates a LeakyBucket limiter" do
        limiter = RedLine.leaky("test", 60, :minute)
        expect(limiter).to be_a(RedLine::Limiters::LeakyBucket)
        expect(limiter.bucket_size).to eq(60)
      end
    end

    describe ".points" do
      it "creates a Points limiter" do
        limiter = RedLine.points("test", 1000, 50)
        expect(limiter).to be_a(RedLine::Limiters::Points)
        expect(limiter.bucket_points).to eq(1000)
        expect(limiter.refill_rate).to eq(50.0)
      end
    end

    describe ".unlimited" do
      it "creates an Unlimited limiter" do
        limiter = RedLine.unlimited
        expect(limiter).to be_a(RedLine::Limiters::Unlimited)
      end
    end
  end
end
