-- Initialize concurrent limiter slots if needed
-- KEYS[1] = slots key
-- KEYS[2] = locks hash key
-- ARGV[1] = limit
-- ARGV[2] = ttl
-- Returns: number of slots created

local slots_key = KEYS[1]
local locks_key = KEYS[2]
local limit = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])

-- Only initialize if key doesn't exist
local exists = redis.call('EXISTS', slots_key)
if exists == 0 then
  -- Check if there are held locks (from a previous init)
  local held_locks = redis.call('HLEN', locks_key)
  local slots_to_add = limit - held_locks
  for i = 1, slots_to_add do
    redis.call('RPUSH', slots_key, '1')
  end
  if slots_to_add > 0 then
    redis.call('EXPIRE', slots_key, ttl)
  end
  return slots_to_add
end
redis.call('EXPIRE', slots_key, ttl)
return 0
