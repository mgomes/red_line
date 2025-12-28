-- Safe concurrent lock release
-- KEYS[1] = slots key
-- KEYS[2] = locks hash key
-- ARGV[1] = lock_id (caller's unique identifier)
-- ARGV[2] = ttl
-- Returns: 1 if released, 0 if not found

local slots_key = KEYS[1]
local locks_key = KEYS[2]
local lock_id = ARGV[1]
local ttl = tonumber(ARGV[2])

local held = redis.call('HDEL', locks_key, lock_id)
if held == 1 then
  redis.call('RPUSH', slots_key, '1')
  redis.call('EXPIRE', slots_key, ttl)
  redis.call('EXPIRE', locks_key, ttl)
  return 1
end
return 0
