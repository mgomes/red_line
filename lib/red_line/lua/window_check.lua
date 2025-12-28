-- Sliding window check and add
-- KEYS[1] = window key
-- ARGV[1] = current_time (float)
-- ARGV[2] = window_duration (seconds)
-- ARGV[3] = limit
-- ARGV[4] = unique_id (for member)
-- ARGV[5] = ttl
-- Returns: {count, success (1/0), wait_time}

local key = KEYS[1]
local now = tonumber(ARGV[1])
local duration = tonumber(ARGV[2])
local limit = tonumber(ARGV[3])
local unique_id = ARGV[4]
local ttl = tonumber(ARGV[5])

local window_start = now - duration

-- Remove expired entries
redis.call('ZREMRANGEBYSCORE', key, '-inf', window_start)

-- Count current entries
local count = redis.call('ZCARD', key)

if count < limit then
  redis.call('ZADD', key, now, unique_id)
  redis.call('EXPIRE', key, ttl)
  return {count + 1, 1, 0}
else
  -- Get oldest entry to calculate wait time
  local oldest = redis.call('ZRANGE', key, 0, 0, 'WITHSCORES')
  local wait_time = 0
  if #oldest >= 2 then
    local oldest_ts = tonumber(oldest[2])
    wait_time = (oldest_ts + duration) - now
    if wait_time < 0 then
      wait_time = 0
    end
  end
  return {count, 0, wait_time}
end
