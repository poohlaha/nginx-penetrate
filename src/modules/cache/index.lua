--[[
    缓存, 使用 sha256 加密 uri, 作为 redis 的 key 存储
--]]
local json = require('dkjson')
local Utils = require('modules.utils.index')
local Redis = require('modules.redis.index')

local loggerPrefix = '[Nginx Lua Cache]'

local Cache = {}
Cache.__index = Cache

function Cache:new(cacheTime, redisConfig)
    self.cacheTime = cacheTime
    self.redisConfig = redisConfig
    return self
end

-- set
function Cache:set(address, result, uri, params)
    local cacheTime = self.cacheTime

    do
        if Utils.isNull(cacheTime) then
            ngx.log(ngx.ERR, loggerPrefix, 'cache time is: ', cacheTime, ' use no cache !')
            return
        end

        if type(cacheTime) == 'string' then
            cacheTime = tonumber(cacheTime)
        end

        if (cacheTime <= 0) then
            ngx.log(ngx.ERR, loggerPrefix, 'cache time is: ', cacheTime, ' use no cache !')
            return
        end

        ngx.log(ngx.ERR, loggerPrefix, 'cache time is: ', cacheTime)
    end

    do
        if Utils.isNull(address) then
            ngx.log(ngx.ERR, loggerPrefix, 'address is nil .')
            return
        end

        if Utils.isNull(uri) then
            ngx.log(ngx.ERR, loggerPrefix, 'uri is nil .')
            return
        end

        if not result then
            ngx.log(ngx.ERR, loggerPrefix, 'result is nil .')
            return
        end

        if not self.redisConfig then
            ngx.log(ngx.ERR, loggerPrefix, 'redisConfig is nil .')
            return nil
        end

        if Utils.isObjectNull(params) then
            ngx.log(ngx.WARN, loggerPrefix, 'params is nil .')
        end
    end

    do
        local redisClient = Redis:new(self.redisConfig)
        if not redisClient then
            return nil
        end

        local opts = {
            uri = uri,
            params = params,
            time = os.date("%Y%m%d%H%M%S", os.time()), --存储时间
            result = result
        }

        local key = self:generateKey(redisClient, address, uri)

        ngx.log(ngx.DEBUG, loggerPrefix, 'cache key for redis: ', key)
        ngx.log(ngx.DEBUG, loggerPrefix, 'cache opts for redis ', json.encode(opts))

        redisClient:psetex(key, json.encode(opts), cacheTime)
        redisClient:close()
    end
end

-- 生成 key
function Cache:generateKey(redisClient, address, uri)
    local key

    do
        -- 判断 key 是否存在
        ngx.log(ngx.DEBUG, loggerPrefix, 'original key for redis: ', uri)
        key = Utils.getEncryptionKey(uri)
        key = address .. '-' .. key
        local value = redisClient:get(key)
        if not value then
            return key
        end
    end

    do
        ngx.log(ngx.DEBUG, loggerPrefix, 'redis 存在 key: ', key, ', 开始生成带随机数后缀的 key !')
        -- local random = math.randomseed(tostring(os.time()):reverse():sub(1, 7)) -- 有错

        -- 生成随机数种子
        math.randomseed(os.time())
        local random = math.random(100, 10000) -- 生成随机数
        ngx.log(ngx.DEBUG, loggerPrefix, 'random: ', random)

        while(random) do
            local v = redisClient:get(key .. '-' .. random)
            ngx.log(ngx.DEBUG, loggerPrefix, 'random key: ', key .. '-' .. random)
            if not v then
                break
            else
                random = math.random(100, 10000)
            end
        end

        return key .. '-' .. random
    end
end

-- get
function Cache:get(address, uri, params)
    do
        if Utils.isNull(address) then
            ngx.log(ngx.ERR, loggerPrefix, 'address is nil .')
            return
        end

        if Utils.isNull(uri) then
            ngx.log(ngx.ERR, loggerPrefix, 'uri is nil .')
            return
        end

        if Utils.isObjectNull(params) then
            ngx.log(ngx.WARN, loggerPrefix, 'params is nil .')
        end
    end

    do
        local redisClient = Redis:new(self.redisConfig)
        if not redisClient then
            return nil
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'original key for redis: ', uri)
        local key = Utils.getEncryptionKey(uri)
        key = address .. '-' .. key
        local value = redisClient:get(key)
        ngx.log(ngx.DEBUG, loggerPrefix, 'redis 中 key 为:', key)

        -- 如果有值，且没有参数，直接返回
        if value then
            -- 没有参数不需要比较
            if Utils.isObjectNull(params) then
                ngx.log(ngx.DEBUG, loggerPrefix, '获取到缓存数据 !')
                redisClient:close()
                return value.result
            end

            local isSame = Utils.compareTables(params, value.params)
            if isSame and value.uri == uri then
                ngx.log(ngx.DEBUG, loggerPrefix, '获取到缓存数据')
                redisClient:close()
                return value.result
            else
                value = nil
            end
        end

        ngx.log(ngx.DEBUG, loggerPrefix, '从 ' .. key .. '-' .. ' 开头的键找数据 ....')

        -- 获取以 key- 为开头开头的所有键
        local keys = redisClient:getKeys(key .. '-')
        ngx.log(ngx.DEBUG, loggerPrefix, 'keys: ', json.encode(keys))
        if not keys then
            ngx.log(ngx.DEBUG, loggerPrefix, '没有获取到缓存数据 !')
            redisClient:close()
            return nil
        end

        for _, k in ipairs(keys) do
            local v = redisClient:get(k)
            if Utils.isObjectNull(params) then
                if v and uri == v.uri then
                    value = v
                end
            end

            -- 比较参数是否一致
            local isSame = Utils.compareTables(params, v.params)
            if isSame and v.uri == uri then
                ngx.log(ngx.DEBUG, loggerPrefix, '获取到缓存数据, key 为: ', k)
                value = v
            end
        end

        redisClient:close()

        if Utils.isNull(value) then
            ngx.log(ngx.DEBUG, loggerPrefix, '没有获取到缓存数据 !')
            return nil
        end

        if (type(value) == 'string') then
            value = json.decode(value)
        end

        if not value then
            return nil
        end

        return value.result
    end
end

return Cache