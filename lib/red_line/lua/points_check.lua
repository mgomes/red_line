-- Points-based rate limit check
-- KEYS[1] = points key
-- ARGV[1] = current_time
-- ARGV[2] = bucket_points (initial capacity)
-- ARGV[3] = refill_rate (points per second)
-- ARGV[4] = estimated_cost
-- ARGV[5] = ttl
-- Returns: {available_points, success (1/0), wait_time}

local key = KEYS[1]
local now = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local refill_rate = tonumber(ARGV[3])
local cost = tonumber(ARGV[4])
local ttl = tonumber(ARGV[5])

-- Get current state
local state = redis.call('HGETALL', key)
local points = capacity
local last_refill = now

if #state > 0 then
  for i = 1, #state, 2 do
    if state[i] == 'points' then
      points = tonumber(state[i+1]) or capacity
    elseif state[i] == 'last_refill' then
      last_refill = tonumber(state[i+1]) or now
    end
  end
end

-- Refill based on time elapsed
local elapsed = now - last_refill
local refilled = elapsed * refill_rate
points = math.min(capacity, points + refilled)

-- Check if we have enough points
if points >= cost then
  points = points - cost
  redis.call('HSET', key, 'points', points, 'last_refill', now)
  redis.call('EXPIRE', key, ttl)
  return {points, 1, 0}
else
  -- Calculate wait time for enough points
  local needed = cost - points
  local wait_time = needed / refill_rate
  return {points, 0, wait_time}
end
