-- Atomically acquire a slot and record the lock
-- KEYS[1] = slots key
-- KEYS[2] = locks hash key
-- ARGV[1] = lock_id
-- ARGV[2] = current_time
-- ARGV[3] = ttl
-- Returns: 1 if acquired, 0 if no slot available

local slots_key = KEYS[1]
local locks_key = KEYS[2]
local lock_id = ARGV[1]
local current_time = ARGV[2]
local ttl = tonumber(ARGV[3])

-- Try to get a slot
local slot = redis.call('LPOP', slots_key)
if slot then
  -- Atomically record the lock
  redis.call('HSET', locks_key, lock_id, current_time)
  redis.call('EXPIRE', locks_key, ttl)
  return 1
end

return 0
