# RedLine

A Redis-backed rate limiting library for Ruby. RedLine provides distributed rate limiting across multiple processes and servers, making it suitable for multi-process web applications, background job systems, and microservices.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'red_line'
```

Then execute:

```
$ bundle install
```

Or install it directly:

```
$ gem install red_line
```

## Configuration

Configure RedLine once during application startup:

```ruby
RedLine.configure do |config|
  # Redis connection
  config.redis_url = ENV['REDIS_URL']
  # Or configure host/port separately:
  # config.redis_host = 'localhost'
  # config.redis_port = 6379
  # config.redis_db = 0
  # config.redis_password = 'secret'

  # Connection pool settings
  config.pool_size = 10          # Number of Redis connections
  config.pool_timeout = 5        # Seconds to wait for a connection

  # Default limiter settings
  config.default_wait_timeout = 5   # Seconds to wait before raising OverLimit
  config.default_lock_timeout = 30  # Seconds before a concurrent lock can be reclaimed
  config.default_ttl = 7776000      # 90 days in seconds, metadata cleanup
end
```

## Basic Usage

Limiters are designed to be created once and reused. They are thread-safe.

```ruby
# Create limiters at startup
API_LIMIT = RedLine.bucket('external-api', 100, :second)

# Use them anywhere in your application
def call_api
  API_LIMIT.within_limit do
    # Your API call here
  end
end
```

If the rate limit is exceeded and cannot be satisfied within `wait_timeout`, RedLine raises `RedLine::OverLimit`:

```ruby
begin
  limiter.within_limit { do_work }
rescue RedLine::OverLimit => e
  puts "Rate limited: #{e.message}"
  puts "Retry after: #{e.retry_after} seconds" if e.retry_after
end
```

## Limiter Types

### Concurrent

Limits the number of operations that can happen simultaneously. Uses Redis lists with BLPOP for efficient blocking waits (no polling).

```ruby
# Allow 50 concurrent operations
ERP_LIMIT = RedLine.concurrent('erp', 50,
  wait_timeout: 5,    # Wait up to 5 seconds for a slot
  lock_timeout: 30    # Reclaim locks held longer than 30 seconds
)

ERP_LIMIT.within_limit do
  # Only 50 of these can run at once across all processes
  call_erp_system
end
```

Options:
- `wait_timeout` - Seconds to wait for an available slot (default: 5)
- `lock_timeout` - Seconds before a lock can be reclaimed from a crashed process (default: 30)
- `policy` - `:raise` (default) or `:ignore` to silently skip the block

The concurrent limiter tracks metrics:

```ruby
ERP_LIMIT.held      # Number of currently held locks
ERP_LIMIT.metrics   # Hash with held, held_time, immediate, waited, wait_time, overages, reclaimed
```

**Important**: Ensure your operations complete within `lock_timeout` seconds. If an operation exceeds this duration, another process may reclaim the lock, potentially causing rate limit violations.

### Bucket (Fixed Window)

Limits operations to N per time bucket. Each bucket is a fixed time interval.

```ruby
# 100 requests per second
RATE_LIMIT = RedLine.bucket('api', 100, :second, wait_timeout: 2)

# 1000 requests per minute
MINUTE_LIMIT = RedLine.bucket('api-minute', 1000, :minute)

# Custom interval: 50 requests per 30 seconds
CUSTOM_LIMIT = RedLine.bucket('custom', 50, 30)
```

Intervals: `:second`, `:minute`, `:hour`, `:day`, or any number of seconds.

Behavior:
- For `:second` intervals, the limiter sleeps and retries within `wait_timeout`
- For larger intervals, the limiter raises `OverLimit` immediately when the limit is reached

```ruby
limiter.remaining  # Returns remaining capacity in current bucket
```

### Window (Sliding Window)

Limits operations using a sliding time window. Unlike bucket limiting, the window starts from the time of each request, preventing bursts at bucket boundaries.

```ruby
# 5 requests per second, sliding
WINDOW_LIMIT = RedLine.window('stripe', 5, :second, wait_timeout: 5)

# Custom window: 10 requests per 30 seconds
CUSTOM_WINDOW = RedLine.window('custom', 10, 30)
```

The limiter sleeps in 0.5 second intervals and retries until `wait_timeout` is reached.

```ruby
limiter.remaining  # Returns remaining capacity in current window
```

### Leaky Bucket

Allows bursting up to a bucket size, then limits to a steady drip rate. Useful for APIs that allow occasional bursts but enforce an average rate.

```ruby
# Bucket holds 60, drains in 60 seconds (1 per second steady rate)
SHOPIFY_LIMIT = RedLine.leaky('shopify', 60, :minute)

# Equivalent using seconds
SHOPIFY_LIMIT = RedLine.leaky('shopify', 60, 60)

# Bucket of 40, drains at 2 per second (empties in 20 seconds)
FAST_DRAIN = RedLine.leaky('fast', 40, 20)
```

The first parameter is the bucket size (burst capacity). The second parameter is how long it takes to drain a full bucket.

```ruby
limiter.level  # Returns current bucket level (0.0 to bucket_size)
```

### Points

Points-based rate limiting for APIs that charge different costs per operation, such as GraphQL endpoints.

```ruby
# 1000 points, refills at 50 points per second
GRAPHQL_LIMIT = RedLine.points('graphql', 1000, 50)

GRAPHQL_LIMIT.within_limit(estimate: 200) do |handle|
  result = execute_query

  # Adjust if actual cost differs from estimate
  actual_cost = result.query_cost
  handle.points_used(actual_cost)
end
```

The `estimate` parameter reserves points before the operation. After the operation, call `handle.points_used(actual)` to correct the reservation if the actual cost differs.

```ruby
limiter.available_points  # Returns currently available points
```

### Unlimited

A limiter that always allows execution. Useful for testing or bypassing limits for certain users.

```ruby
ADMIN_LIMIT = RedLine.unlimited

# In your code
def get_limiter(user)
  user.admin? ? RedLine.unlimited : STANDARD_LIMIT
end
```

The unlimited limiter does not require Redis.

## Policies

All limiters accept a `policy` option:

- `:raise` (default) - Raise `RedLine::OverLimit` when the limit cannot be satisfied
- `:ignore` - Return `nil` and skip the block silently

```ruby
limiter = RedLine.bucket('optional', 10, :second, policy: :ignore)

result = limiter.within_limit { expensive_operation }
if result.nil?
  # Block was skipped due to rate limit
end
```

## Dynamic Limiter Names

Limiter names can include dynamic components for per-user or per-resource limits:

```ruby
def call_stripe(user_id)
  limiter = RedLine.bucket("stripe-#{user_id}", 30, :second)
  limiter.within_limit do
    # Each user gets their own 30/second limit
  end
end
```

Names must contain only letters, numbers, hyphens, and underscores.

**Note**: Creating limiters is relatively inexpensive, but for hot paths consider caching them:

```ruby
class RateLimits
  def self.for_user(user_id)
    @user_limits ||= {}
    @user_limits[user_id] ||= RedLine.bucket("user-#{user_id}", 100, :minute)
  end
end
```

## TTL and Cleanup

Limiter metadata in Redis expires after a configurable TTL (default: 90 days). For applications that create many dynamic limiters, consider a shorter TTL:

```ruby
# Expire after 2 weeks
limiter = RedLine.bucket('temp', 10, :second, ttl: 1209600)
```

## Error Handling

```ruby
begin
  limiter.within_limit { do_work }
rescue RedLine::OverLimit => e
  e.limiter_name   # Name of the limiter
  e.limiter_type   # 'bucket', 'window', 'concurrent', etc.
  e.limit          # The configured limit
  e.current        # Current count or level
  e.retry_after    # Suggested wait time in seconds (may be nil)
end
```

Other exceptions:

- `RedLine::InvalidName` - Raised when a limiter name contains invalid characters
- `RedLine::ConnectionError` - Raised for Redis connection issues
- `RedLine::LockLost` - Raised if a concurrent lock is reclaimed while held

## Caveats and Important Notes

### Clock Synchronization

All servers using RedLine should synchronize their clocks using NTP. Rate limiting calculations depend on consistent time across processes. Clock drift can cause inaccurate rate limiting.

### Concurrent Limiter Lock Timeout

The concurrent limiter uses `lock_timeout` to reclaim locks from crashed processes. If your operation takes longer than `lock_timeout`:

1. Another process may reclaim your lock
2. Both processes will be executing simultaneously
3. This violates the concurrency limit

Always set `lock_timeout` higher than your longest expected operation time. Monitor the `overages` and `reclaimed` metrics to detect problems.

### Redis Latency

Rate limiting adds Redis round-trips to your operations. For high-throughput applications:

- Use a Redis instance close to your application servers
- Consider the `pool_size` configuration for concurrent access
- The concurrent limiter uses BLPOP which holds a connection while waiting

### Limiter Reuse

Create limiter instances once and reuse them. While creating limiters is not expensive, reusing them avoids repeated name validation and key generation:

```ruby
# Good: Create once at startup
LIMIT = RedLine.bucket('api', 100, :second)

# Avoid: Creating in hot paths
def process
  RedLine.bucket('api', 100, :second).within_limit { work }
end
```

### Nested Limiters

RedLine does not support composing multiple limiters atomically. This pattern does not work correctly:

```ruby
# This does NOT enforce both limits correctly
HOURLY.within_limit do
  MINUTELY.within_limit do
    # May violate hourly limit
  end
end
```

Instead, enforce the smaller limit and let the remote service handle the larger limit, or implement custom logic to track both.

### Script Caching

RedLine caches Lua script SHAs for performance. If Redis is restarted and scripts are evicted, RedLine automatically reloads them on the next call. This is transparent but may cause a brief latency spike.

### Testing

For tests, use the unlimited limiter to avoid Redis dependencies:

```ruby
# In test setup
def setup
  @original_limiter = MyService::RATE_LIMIT
  MyService.const_set(:RATE_LIMIT, RedLine.unlimited)
end

def teardown
  MyService.const_set(:RATE_LIMIT, @original_limiter)
end
```

Or configure a separate Redis database for tests:

```ruby
# spec/spec_helper.rb
RedLine.configure do |config|
  config.redis_db = 15
end

RSpec.configure do |config|
  config.before(:each) do
    RedLine.connection.call('FLUSHDB')
  end
end
```

## Thread Safety

All limiter instances are thread-safe and designed to be shared across threads. The underlying Redis connection pool handles concurrent access.

## License

MIT License
