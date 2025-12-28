-- Leaky bucket check
-- KEYS[1] = bucket key
-- ARGV[1] = current_time
-- ARGV[2] = bucket_size (capacity)
-- ARGV[3] = drain_rate (drips per second)
-- ARGV[4] = ttl
-- Returns: {level, success (1/0), wait_time}

local key = KEYS[1]
local now = tonumber(ARGV[1])
local capacity = tonumber(ARGV[2])
local drain_rate = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

-- Get current state
local state = redis.call('HGETALL', key)
local level = 0
local last_drip = now

if #state > 0 then
  for i = 1, #state, 2 do
    if state[i] == 'level' then
      level = tonumber(state[i+1]) or 0
    elseif state[i] == 'last_drip' then
      last_drip = tonumber(state[i+1]) or now
    end
  end
end

-- Calculate drip since last call
local elapsed = now - last_drip
local drained = elapsed * drain_rate
level = math.max(0, level - drained)

-- Check if we can add one more drop without overflow
if level + 1 <= capacity then
  level = level + 1
  redis.call('HSET', key, 'level', level, 'last_drip', now)
  redis.call('EXPIRE', key, ttl)
  return {level, 1, 0}
else
  -- Calculate wait time for next available slot
  -- Need to drain until level + 1 <= capacity, i.e., level <= capacity - 1
  local excess = level - (capacity - 1)
  local wait_time = excess / drain_rate
  if wait_time < 0 then wait_time = 0 end
  return {level, 0, wait_time}
end
