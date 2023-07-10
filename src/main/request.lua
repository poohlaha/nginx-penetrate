--[[
    发送请求
--]]
local json = require('dkjson')
local Utils = require('modules.utils.index')
local Https = require('modules.https.index')
local Http = require('modules.http.index')
local Redis = require('modules.redis.index')

local loggerPrefix = '[Nginx Lua Request]'

local Request = {}
Request.__index = Request

function Request:new(params, args, uri, redisConfig, config)
    self.params = params
    self.args = args
    self.uri = uri
    self.redisConfig = redisConfig
    self.config = config
    return self
end

-- 发送请求
function Request:send(headers)
    ngx.log(ngx.DEBUG, loggerPrefix, 'send request ...')
    do
        if not self.params then
            ngx.log(ngx.ERR, loggerPrefix, 'params is nil .')
            return nil
        end

        if not self.config then
            ngx.log(ngx.ERR, loggerPrefix, 'config is nil .')
            return nil
        end

        if not self.redisConfig then
            ngx.log(ngx.ERR, loggerPrefix, 'redisConfig is nil .')
            return nil
        end

        if Utils.isNull(self.params.url) then
            ngx.log(ngx.ERR, loggerPrefix, 'url is nil .')
            return nil
        end

        if Utils.isNull(self.params.address) then
            ngx.log(ngx.ERR, loggerPrefix, 'address is nil .')
            return nil
        end
    end

    local result
    do
        ngx.log(ngx.DEBUG, loggerPrefix, 'request params:', json.encode(self.params))
        -- 发送请求
        if string.upper(self.params.protocol) == 'HTTPS' then
            result = self:sendHttpsRequest(headers)
        elseif string.upper(self.params.protocol) == 'HTTP' then
            result = self:sendHttpRequest(headers)
        else
            ngx.log(ngx.ERR, loggerPrefix, '非法协议 .')
            return nil
        end
    end

    do
        -- 处理返回结果
        if not result then
            ngx.log(ngx.ERR, loggerPrefix, '发送请求失败, 未获取到结果 .')
            return nil
        end

        return result
    end
end

-- 从头中获取 token 和 host
function Request:getToken(headers)
    local tokenName = self.params.localTokenName
    local token

    do
        if not headers or Utils.isNull(tokenName) then
            ngx.log(ngx.ERR, loggerPrefix, 'headers 中未有 token 传递 ...')
            return nil
        end

        token = headers[tokenName]
        if Utils.isNull(token) then
            ngx.log(ngx.ERR, loggerPrefix, 'headers 中 token is nil...')
            return nil
        end
    end

    return token
end

-- 从 Redis 中获取数据
function Request:getValueByRedis()
    local redisClient = Redis:new(self.redisConfig)
    if not redisClient then
        return nil
    end

    local result = redisClient:get(self.params.address)
    redisClient:close()

    if not result then
        return nil
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'redis 中的值: ', json.encode(result))
    return result
end

-- 判断 host 和 token 是否一致
function Request:judge(result, token)
    local host = (self.params.protocol or '') .. '://' .. (self.params.host or '')
    ngx.log(ngx.DEBUG, loggerPrefix, '请求 host: ', host)
    ngx.log(ngx.DEBUG, loggerPrefix, '请求 token: ', token)

    if not result then
        return false
    end

    if (result.host ~= host) then
        ngx.log(ngx.ERR, loggerPrefix, 'host 不一致, 非法请求!')
        return false
    end

    if (result.localToken ~= token) then
        ngx.log(ngx.ERR, loggerPrefix, 'token 不一致, 非法请求!')
        return false
    end

    return true
end

-- 获取真实的 token
function Request:getRealToken(headers)
    local token = self:getToken(headers)
    local result = self:getValueByRedis()

    if not self:judge(result, token) then
        return nil
    end

    if (result.localToken ~= token) then
        ngx.log(ngx.ERR, loggerPrefix, 'token 不一致, 非法请求!')
        return nil
    end

    return result.realToken or ''
end

-- 获取请求头, 非 login 且需要鉴权, 就要传 headers
function Request:getHeaders(headers)
    local h = {}
    if self.params.type ~= 1 and self.params.auth then
        ngx.log(ngx.DEBUG, loggerPrefix, 'set headers ...')
        local realToken = self:getRealToken(headers)
        if Utils.isNull(realToken) then
            return nil
        end

        if Utils.isNull(self.params.header) then
            h[self.params.tokenName] = realToken
        else -- 拼装header
            local header = self.params.header
            header = string.gsub(header, "%$1", realToken)
            h[self.params.tokenName] = header
        end
    else -- 设置头
        local header = self.params.header
        if not Utils.isNull(self.params.header) then
            h[self.params.tokenName] = header
        end
    end

    return h
end

-- 发送 http 请求
function Request:sendHttpRequest(headers)
    local opts = { method = self.params.method or 'POST' }
    opts.keepalive_timeout = self.params.timeout or self.config.timeout -- 超时
    opts.headers = self:getHeaders(headers)

    if not opts.headers then
        return nil
    end

    ngx.log(ngx.DEBUG, loggerPrefix, '发送 http 请求 ...')
    -- 封装 url, 带参数在后面
    local url = self.params.url or ''
    if string.upper(self.params.method) == 'GET' then
        -- 拼装 url, 加上参数
        url = url .. '?'
        for i, v in pairs(self.args) do
            url = url .. (i .. '=' .. v)
        end
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'get request url: ', url)
    local client = Http:new(url, opts)
    return client:send()
end

-- 发送 https 请求
function Request:sendHttpsRequest(headers)
    local opts = { method = self.params.method or 'POST' }
    opts.keepalive_timeout = self.params.timeout or self.config.timeout -- 超时
    opts.headers = self:getHeaders(headers)

    if not opts.headers then
        return nil
    end

    ngx.log(ngx.DEBUG, loggerPrefix, '发送 https 请求 ...')
    local client = Https:new({
        url = self.params.url,
        body = self.args,
        method = opts.method,
        headers = opts.headers,
        useSslVerify = false
    })
    return client:send()
end

-- 退出登录操作
function Request:operateLogout(headers)
    local realToken = self:getRealToken(headers)
    if Utils.isNull(realToken) then
        return false
    end

    -- 删除 redis 值
    local redisClient = Redis:new(self.redisConfig)
    if not redisClient then
        return nil
    end

    -- 删除所有以 address 和 address- 开头 key 的值
    redisClient:del(self.params.address)
    redisClient:delKeys(self.params.address .. '-')
    redisClient:delKeys(self.params.address .. '-random-')
    redisClient:close()
end

return Request