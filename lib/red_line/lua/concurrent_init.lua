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

-- Check current state
local current_slots = redis.call('LLEN', slots_key)
local held_locks = redis.call('HLEN', locks_key)
local total_known = current_slots + held_locks

-- Only add slots if we're below the limit
-- This handles: initial creation, recovery after crash, and prevents
-- re-initialization when list is empty because all slots are held
if total_known < limit then
  local slots_to_add = limit - total_known
  for i = 1, slots_to_add do
    redis.call('RPUSH', slots_key, '1')
  end
  if slots_to_add > 0 then
    redis.call('EXPIRE', slots_key, ttl)
  end
  return slots_to_add
end

-- Refresh TTL if slots exist
if current_slots > 0 then
  redis.call('EXPIRE', slots_key, ttl)
end
return 0
