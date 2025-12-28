-- Initialize concurrent limiter slots exactly once
-- KEYS[1] = slots key
-- KEYS[2] = locks hash key
-- KEYS[3] = init sentinel key
-- ARGV[1] = limit
-- ARGV[2] = ttl
-- Returns: number of slots created

local slots_key = KEYS[1]
local locks_key = KEYS[2]
local init_key = KEYS[3]
local limit = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])

-- Check if already initialized using sentinel key
local already_init = redis.call('EXISTS', init_key)
if already_init == 1 then
  -- Refresh TTL on slots if they exist
  local current_slots = redis.call('LLEN', slots_key)
  if current_slots > 0 then
    redis.call('EXPIRE', slots_key, ttl)
  end
  redis.call('EXPIRE', init_key, ttl)
  return 0
end

-- Try to atomically claim initialization rights
-- SETNX returns 1 if we set it, 0 if it already existed
local claimed = redis.call('SETNX', init_key, '1')
if claimed == 1 then
  redis.call('EXPIRE', init_key, ttl)
  -- We won the race - initialize slots
  for i = 1, limit do
    redis.call('RPUSH', slots_key, '1')
  end
  redis.call('EXPIRE', slots_key, ttl)
  return limit
end

-- Another process beat us to initialization
return 0
