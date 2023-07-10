--[[
    连接redis, 读取 redis 数据
    地址: https://github.com/openresty/lua-resty-redis
    安装:
        - 使用 make: make install PREFIX=/home/nginx-resty
        - 使用 opm: opm get openresty/lua-resty-redis
    测试: curl -X GET http://localhost:9999/testRedis
--]]
local json = require('dkjson')
local redis = require('resty.redis')
local Utils = require('modules.utils.index')
local loggerPrefix = '[Nginx Lua Redis]'

local Redis = {}
Redis.__index = Redis

--[[
    opts: {
        host: '', // host
        port: 6379, // port
        auth: '', // password
    }
--]]
function Redis:new(opts)
    self.opts = opts
    self.client = self:connect()
    return self
end

-- connect
function Redis:connect()
    do
        local opts = self.opts
        if not opts then
            ngx.log(ngx.ERR, loggerPrefix, 'opts is nil .')
            return nil
        end

        if Utils.isNull(opts.host) then
            ngx.log(ngx.ERR, loggerPrefix, 'host is nil in opts .')
            return nil
        end
    end

    local client = redis:new()

    do
        -- 账号密码
        local host = self.opts.host
        local port = self.opts.port or 6379
        local ok, error = client:connect(host, port)

        -- nil
        if not ok then
            ngx.log(ngx.ERR, loggerPrefix, 'connect to redis error: ', error)
            return nil
        end
    end

    do
        local auth = self.opts.auth
        if auth then
            local res, err = client:auth(auth)
            -- nil
            if not res then
                ngx.log(ngx.ERR, loggerPrefix, 'redis password incorrect: ', err)
                return nil
            end
        end
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'connect to redis success !')
    return client
end

function Redis:validate(name)
    do
        if not self.client then
            ngx.log(ngx.ERR, loggerPrefix, 'client is not connect .')
            return false
        end
    end

    do
        if Utils.isNull(name) then
            ngx.log(ngx.ERR, loggerPrefix, 'name is nil .')
            return false
        end
    end

    return true
end

-- set
function Redis:set(name, value)
    do
        if not self:validate(name) then
            return false
        end
    end

    do
        local ok, err = self.client:set(name, tostring(value))
        if not ok then
            ngx.log(ngx.ERR, loggerPrefix, 'set ' .. name .. ' to redis error: ', err)
            return false
        end
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'set ' .. name .. ' to redis success !')
    return true
end

-- psetex, 设置过期时间(毫秒)
function Redis:psetex(name, value, expireTime)
    do
        if not self:validate(name) then
            return false
        end

        if not expireTime then
            ngx.log(ngx.ERR, loggerPrefix, 'expireTime is nil .')
            return false
        end
    end

    do
        -- setex: 秒, psetex: 毫秒
        local ok, err = self.client:psetex(name, expireTime, tostring(value))
        if not ok then
            ngx.log(ngx.ERR, loggerPrefix, 'psetex ' .. name .. ' to redis error: ', err)
            return false
        end
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'psetex ' .. name .. ' to redis success !')
    return true
end

-- get
function Redis:get(name)
    do
        if not self:validate(name) then
            return nil
        end
    end

    do
        local res, err = self.client:get(name)
        if not res then
            ngx.log(ngx.ERR, loggerPrefix, 'get ' .. name .. ' from redis error: ', err)
            return nil
        end

        if res == ngx.null then
            ngx.log(ngx.ERR, loggerPrefix, 'can not find name: ' .. name)
            return nil
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'name: ' .. name, ' value: ' .. res)

        if Utils.isNull(res) then
            return nil
        end

        local result = json.decode(res)
        if not result then
            return nil
        end

        return result
    end
end

-- del
function Redis:del(name)
    do
        if not self:validate(name) then
            return nil
        end
    end

    do
        local res, err = self.client:del(name)
        if not res then
            ngx.log(ngx.ERR, loggerPrefix, 'del ' .. name .. ' from redis error: ', err)
            return nil
        end

        if res == ngx.null then
            ngx.log(ngx.ERR, loggerPrefix, 'can not del name: ' .. name)
            return nil
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'delete ' .. name .. ' success !')
        return res
    end
end

-- 删除以 prefix 为前缀的所有数据
function Redis:delKeys(prefix)
    do
        -- 获取以指定前缀开头的所有键
        local keys = self:getKeys(prefix)
        if not keys then
            return
        end

        -- 删除匹配的键
        for _, key in ipairs(keys) do
            self:del(key)
            ngx.log(ngx.ERR, loggerPrefix, 'delete key: ', key)
        end
    end
end

-- 获取 keys
function Redis:getKeys(prefix)
    do
        if Utils.isNull(prefix) then
            ngx.log(ngx.ERR, loggerPrefix, 'prefix is nil .')
            return nil
        end

        if not self.client then
            ngx.log(ngx.ERR, loggerPrefix, 'client is not connect .')
            return nil
        end

        if not self.client then
            ngx.log(ngx.ERR, loggerPrefix, 'client is not connect .')
            return nil
        end
    end

    do
        -- 获取以指定前缀开头的所有键
        ngx.log(ngx.DEBUG, loggerPrefix, '获取 keys, prefix: ', prefix)
        local cursor = '0'
        local keys = {}

        repeat
            local res, err = self.client:scan(cursor, 'MATCH', prefix .. '*')
            if not res then
                ngx.log(ngx.ERR, loggerPrefix, '无法扫描键: ', err)
                return nil
            end

            ngx.log(ngx.ERR, loggerPrefix, '获取到 res: ', json.encode(res))

            cursor = res[1]
            local batchKeys = res[2]

            if batchKeys and #batchKeys > 0 then
                for _, key in ipairs(batchKeys) do
                    table.insert(keys, key)
                end
            end

        until cursor == '0'

        ngx.log(ngx.ERR, loggerPrefix, '获取到 keys: ', json.encode(keys))
        return keys
    end
end


-- 获取键的剩余时间
function Redis:getRemainder(key)
    do
        if not self:validate(name) then
            return nil
        end
    end

    do
        local ttl, err = red:ttl(key)
        if not ttl then
            ngx.log(ngx.ERR, loggerPrefix, 'get remainder from redis error: ', err)
            return nil
        end

        if ttl < 0 then
            ngx.log(ngx.ERR, loggerPrefix, 'redis has no expiration')
            return nil
        end

        return ttl
    end
end

-- close
function Redis:close()
    do
        if not self.client then
            ngx.log(ngx.ERR, loggerPrefix, 'client is not connect .')
            return false
        end
    end

    do
        self.client:close()
    end
end

return Redis



