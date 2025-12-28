-- Atomic bucket increment with expiry
-- KEYS[1] = bucket key
-- ARGV[1] = limit
-- ARGV[2] = ttl in seconds
-- Returns: {current_count, success (1/0), remaining_ttl}

local key = KEYS[1]
local limit = tonumber(ARGV[1])
local ttl = tonumber(ARGV[2])

local current = redis.call('GET', key)
if current == false then
  current = 0
else
  current = tonumber(current)
end

if current < limit then
  local new_val = redis.call('INCR', key)
  if new_val == 1 then
    redis.call('EXPIRE', key, ttl)
  end
  return {new_val, 1, 0}
else
  local remaining_ttl = redis.call('TTL', key)
  if remaining_ttl < 0 then
    remaining_ttl = ttl
  end
  return {current, 0, remaining_ttl}
end
