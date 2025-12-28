-- Adjust points after actual usage known
-- KEYS[1] = points key
-- ARGV[1] = estimated_cost
-- ARGV[2] = actual_cost
-- ARGV[3] = bucket_capacity
-- ARGV[4] = ttl
-- Returns: new points level

local key = KEYS[1]
local estimated = tonumber(ARGV[1])
local actual = tonumber(ARGV[2])
local capacity = tonumber(ARGV[3])
local ttl = tonumber(ARGV[4])

local diff = estimated - actual
local current = tonumber(redis.call('HGET', key, 'points') or 0)
local new_points = math.min(capacity, math.max(0, current + diff))
redis.call('HSET', key, 'points', new_points)
redis.call('EXPIRE', key, ttl)
return new_points
