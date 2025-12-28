# frozen_string_literal: true

RSpec.describe RedLine::Configuration do
  let(:config) { described_class.new }

  describe "defaults" do
    it "has sensible Redis defaults" do
      expect(config.redis_host).to eq("localhost")
      expect(config.redis_port).to eq(6379)
      expect(config.redis_db).to be_nil
      expect(config.redis_url).to be_nil
    end

    it "has sensible pool defaults" do
      expect(config.pool_size).to eq(5)
      expect(config.pool_timeout).to eq(5)
    end

    it "has sensible limiter defaults" do
      expect(config.default_wait_timeout).to eq(5)
      expect(config.default_lock_timeout).to eq(30)
      expect(config.default_policy).to eq(:raise)
    end

    it "has a 90-day default TTL" do
      expect(config.default_ttl).to eq(60 * 60 * 24 * 90)
    end

    it "has a default backoff proc" do
      expect(config.backoff).to be_a(Proc)
      expect(config.backoff.call(nil, 1)).to be_between(5, 10)
      expect(config.backoff.call(nil, 2)).to be_between(10, 15)
    end
  end

  describe "#redis_config" do
    context "with redis_url" do
      before { config.redis_url = "redis://myhost:1234/5" }

      it "includes the URL" do
        expect(config.redis_config[:url]).to eq("redis://myhost:1234/5")
      end

      it "does not include host/port" do
        expect(config.redis_config[:host]).to be_nil
        expect(config.redis_config[:port]).to be_nil
      end

      it "does not include db when not explicitly set" do
        expect(config.redis_config[:db]).to be_nil
      end

      it "includes db when explicitly set" do
        config.redis_db = 10
        expect(config.redis_config[:db]).to eq(10)
      end
    end

    context "without redis_url" do
      it "includes host and port" do
        expect(config.redis_config[:host]).to eq("localhost")
        expect(config.redis_config[:port]).to eq(6379)
      end

      it "does not include db when nil" do
        expect(config.redis_config[:db]).to be_nil
      end

      it "includes db when set" do
        config.redis_db = 3
        expect(config.redis_config[:db]).to eq(3)
      end
    end

    context "with optional settings" do
      it "includes password when set" do
        config.redis_password = "secret"
        expect(config.redis_config[:password]).to eq("secret")
      end

      it "includes timeout when set" do
        config.redis_timeout = 10
        expect(config.redis_config[:timeout]).to eq(10)
      end

      it "includes ssl when set" do
        config.redis_ssl = true
        expect(config.redis_config[:ssl]).to be true
      end
    end
  end
end

RSpec.describe "RedLine.reset!", :redis do
  it "clears the configuration" do
    RedLine.configure { |c| c.pool_size = 99 }
    expect(RedLine.configuration.pool_size).to eq(99)

    RedLine.reset!
    expect(RedLine.configuration.pool_size).to eq(5) # default

    # Restore for other tests
    RedLine.configure do |c|
      if ENV["REDIS_URL"]
        c.redis_url = ENV["REDIS_URL"]
      else
        c.redis_db = 15
      end
    end
  end

  it "clears the connection" do
    conn1 = RedLine.connection
    RedLine.reset!

    # Reconfigure for other tests
    RedLine.configure do |c|
      if ENV["REDIS_URL"]
        c.redis_url = ENV["REDIS_URL"]
      else
        c.redis_db = 15
      end
    end

    conn2 = RedLine.connection
    expect(conn1).not_to equal(conn2)
  end
end

RSpec.describe "Custom TTL", :redis do
  it "uses custom TTL for bucket limiter" do
    limiter = RedLine.bucket("ttl-test", 10, 60, ttl: 120)

    limiter.within_limit { }

    # Verify key exists and has TTL
    ttl = RedLine.connection.call("TTL", "redline:bucket:ttl-test:#{(Time.now.to_i / 60) * 60}")
    expect(ttl).to be > 0
    expect(ttl).to be <= 120
  end

  it "uses custom TTL for window limiter" do
    limiter = RedLine.window("ttl-window", 10, 60, ttl: 120)

    limiter.within_limit { }

    ttl = RedLine.connection.call("TTL", "redline:window:ttl-window")
    expect(ttl).to be > 0
    expect(ttl).to be <= 120
  end
end
