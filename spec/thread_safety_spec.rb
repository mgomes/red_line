# frozen_string_literal: true

RSpec.describe "Thread safety", :redis do
  describe "concurrent limiter under load" do
    # Note: concurrent limiter holds connections during BLPOP, so thread count
    # should not exceed pool_size to avoid connection pool exhaustion
    let(:limiter) { RedLine.concurrent("thread-concurrent", 3, wait_timeout: 2, lock_timeout: 10) }

    it "never exceeds the concurrent limit" do
      max_concurrent = Concurrent::AtomicFixnum.new(0)
      current_concurrent = Concurrent::AtomicFixnum.new(0)
      completed = Concurrent::AtomicFixnum.new(0)

      # Use fewer threads than pool_size (default 5)
      threads = 4.times.map do
        Thread.new do
          5.times do
            begin
              limiter.within_limit do
                current = current_concurrent.increment
                max_concurrent.update { |m| [m, current].max }

                sleep(rand * 0.01) # Random work

                current_concurrent.decrement
                completed.increment
              end
            rescue RedLine::OverLimit
              # Some threads may timeout, that's ok
            end
          end
        end
      end

      threads.each(&:join)

      expect(max_concurrent.value).to be <= 3
      expect(completed.value).to be > 0
    end

    it "properly releases locks on exceptions" do
      # Use a separate limiter with a higher limit to avoid timeouts
      exception_limiter = RedLine.concurrent("thread-exceptions", 10, wait_timeout: 5, lock_timeout: 10)
      error_count = Concurrent::AtomicFixnum.new(0)
      success_count = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do |i|
        Thread.new do
          begin
            exception_limiter.within_limit do
              if i.even?
                raise "intentional error"
              else
                success_count.increment
              end
            end
          rescue RuntimeError
            error_count.increment
          end
        end
      end

      threads.each(&:join)

      expect(error_count.value).to eq(5)
      expect(success_count.value).to eq(5)
      expect(exception_limiter.held).to eq(0)
    end
  end

  describe "bucket limiter under load" do
    let(:limiter) { RedLine.bucket("thread-bucket", 100, 60, wait_timeout: 0) }

    it "accurately counts across threads" do
      success_count = Concurrent::AtomicFixnum.new(0)
      over_limit_count = Concurrent::AtomicFixnum.new(0)

      threads = 20.times.map do
        Thread.new do
          10.times do
            begin
              limiter.within_limit { success_count.increment }
            rescue RedLine::OverLimit
              over_limit_count.increment
            end
          end
        end
      end

      threads.each(&:join)

      # Should have exactly 100 successes and 100 over-limits
      expect(success_count.value).to eq(100)
      expect(over_limit_count.value).to eq(100)
    end
  end

  describe "window limiter under load" do
    let(:limiter) { RedLine.window("thread-window", 50, 60, wait_timeout: 0) }

    it "respects limit across threads" do
      success_count = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do
        Thread.new do
          10.times do
            begin
              limiter.within_limit { success_count.increment }
            rescue RedLine::OverLimit
              # expected
            end
          end
        end
      end

      threads.each(&:join)

      expect(success_count.value).to eq(50)
    end
  end

  describe "points limiter under load" do
    let(:limiter) { RedLine.points("thread-points", 100, 0, wait_timeout: 0) }

    it "tracks points accurately across threads" do
      success_count = Concurrent::AtomicFixnum.new(0)

      threads = 10.times.map do
        Thread.new do
          5.times do
            begin
              limiter.within_limit(estimate: 10) do |handle|
                success_count.increment
                handle.points_used(10)
              end
            rescue RedLine::OverLimit
              # expected after 10 successes
            end
          end
        end
      end

      threads.each(&:join)

      expect(success_count.value).to eq(10)
    end
  end

  describe "shared limiter instance" do
    it "is safe to share across threads" do
      limiter = RedLine.bucket("thread-shared", 1000, 60, wait_timeout: 0)
      results = Concurrent::Array.new

      threads = 100.times.map do |i|
        Thread.new do
          limiter.within_limit { results << i }
        end
      end

      threads.each(&:join)

      expect(results.size).to eq(100)
      expect(results.sort).to eq((0...100).to_a)
    end
  end

  describe "limiter creation is thread-safe" do
    it "handles concurrent limiter creation" do
      limiters = Concurrent::Array.new

      threads = 10.times.map do |i|
        Thread.new do
          limiter = RedLine.bucket("create-#{i}", 10, 60)
          limiters << limiter
        end
      end

      threads.each(&:join)

      expect(limiters.size).to eq(10)
      expect(limiters.map(&:name).sort).to eq((0...10).map { |i| "create-#{i}" })
    end
  end
end
