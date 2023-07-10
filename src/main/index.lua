--[[
  lua.conf 配置(示例):
  ```
    # 匹配以 /chat/v1 开头
    location ^~ /chat/v1 {
      default_type 'application/json'; #返回Json文本
      set $configDir "/home/nginx-code/config/config.json"; # 设置 config.json 地址, 如果没有取默认地址
      content_by_lua_file /home/nginx-code/lib/index.lua;
    }
  ```

  把 `config.xml` 和 `module.xml` 两个文件入到项目(如 chat) 根目录的 `config` 文件夹下
--]]
local json = require('dkjson')
local Utils = require('modules.utils.index')
local XmlParser = require('main.xmlParser')
local Redis = require('modules.redis.index')
local Request = require('main.request')
local Cache = require('modules.cache.index')

-- config.json 默认地址, 通过 nginx 设置
local defaultConfigPath = '/home/nginx-code/config/config.json'
local loggerPrefix = '[Nginx Lua Penetrate]'

local Main = {}
Main.__index = Main
local EXPIRE_TIME = 5 * 60 * 1000  -- 5分钟

-- 错误返回结果
local errorResult = {
    code = ngx.HTTP_INTERNAL_SERVER_ERROR,
    error = {
        reason = ''
    },
    data = {},
    extendData = {}, -- 额外的数据
}

-- init
function Main:new()
    self.uri = ngx.var.uri -- 相对路径
    self.headers = ngx.req.get_headers() -- headers
    self.config = self:getConfig()
    self.args = self:getArgs()
    self.cacheTime = self:getCacheTime() -- 缓存时间
    self.requestRandom = self:getRequestRandom() -- 请求随机数前缀
    return self
end

-- 获取请求参数
function Main:getArgs()
    local method = ngx.req.get_method() or 'POST'

    local args
    if string.upper(method) == 'GET' then
        args = ngx.req.get_uri_args() or {}
    elseif string.upper(method) == 'POST' then
        ngx.req.read_body()
        local postArgs = ngx.req.get_body_data() -- get_post_args 不正确，会多个`{}:true`
        if not postArgs then
            postArgs = {}
        end
        args = json.decode(postArgs, 1, nil)
    end

    return args
end

-- 读取配置文件 config.json
function Main:getConfig()
    local configPath = ngx.var.configPath
    if Utils.isNull(configPath) then
        ngx.log(ngx.DEBUG, loggerPrefix, 'nginx 未配置 config.json 地址, 使用默认地址: ', defaultConfigPath, ' .')
        configPath = defaultConfigPath
    end

    local file = io.open(configPath, "r")
    if not file then
        ngx.log(ngx.DEBUG, loggerPrefix, configPath .. ' 不存在, 使用默认地址: ', defaultConfigPath, ' .')
        file = io.open(defaultConfigPath, "r")
    end
    local data = file:read("*a")
    file:close()
    return json.decode(data, 1, nil)
end

-- 获取缓存时间
function Main:getCacheTime()
    if not self.config then
        return nil
    end

    local cacheTime = ngx.var.cacheTime
    local defaultCacheTime = self.config.cacheTime
    if Utils.isNull(cacheTime) then
        ngx.log(ngx.DEBUG, loggerPrefix, 'cache time is nil, use default cache time: ', defaultCacheTime)
        return defaultCacheTime
    end

    if type(cacheTime) then
        cacheTime = tonumber(cacheTime)
    end

    if cacheTime <= 0 then
        ngx.log(ngx.DEBUG, loggerPrefix, 'use no cache !')
        return nil
    end

    return cacheTime
end

-- 获取请求随机数前缀
function Main:getRequestRandom()
    if not self.config then
        return nil
    end

    local requestRandom = ngx.var.requestRandom
    local defaultRequestRandom = self.config.requestRandom
    if Utils.isNull(requestRandom) then
        ngx.log(ngx.DEBUG, loggerPrefix, 'requestRandom is nil, use default random: ', defaultRequestRandom)
        return defaultRequestRandom
    end

    return requestRandom
end

-- validate
function Main:validate(urls, xmlDir)
    if not self.config then
        ngx.log(ngx.ERR, loggerPrefix, 'config is nil .')
        return false
    end

    -- 不使用穿透
    if not self.config.usePenetrate then
        ngx.log(ngx.ERR, loggerPrefix, 'not use penetrate, exit .')
        return false
    end

    if not self.uri then
        ngx.log(ngx.ERR, loggerPrefix, 'uri is nil .')
        return false
    end

    if Utils.isNull(urls.projectName) or Utils.isNull(urls.url)  then
        ngx.log(ngx.DEBUG, loggerPrefix, self.uri .. ' 解析失败 .')
        return false
    end

    ngx.log(ngx.DEBUG, loggerPrefix, 'projectName:', urls.projectName)
    ngx.log(ngx.DEBUG, loggerPrefix, 'url: ', urls.url)

    if not Utils.isDirExists(xmlDir) then
        ngx.log(ngx.DEBUG, loggerPrefix, 'XML 目录不存在: ', xmlDir)
        return false
    end

    return true
end

-- 分割 url, 获取项目目录
function Main:divideUri()
    local uri = self.uri
    local prefix = string.sub(uri, 1, 1)
    if (prefix == '/') then
        uri = string.sub(uri, 2, #uri)
    end

    -- 查找第一个 /
    local specIndex = string.find(uri, '/')
    local projectName = string.sub(uri, 1, specIndex - 1)
    local url = string.sub(uri, specIndex, #uri)

    return {
        projectName = projectName,
        url = url
    }
end

-- 校验请求随机数, 查看是否为非法请求
function Main:validateRequestRandom(params, uri)
    local redisClient = Redis:new(self.config.redis)
    if not redisClient then
        return false
    end

    local matchedHeaders = {}
    local count = 0
    do
        ngx.log(ngx.DEBUG, loggerPrefix, '请求随机数: ', self.requestRandom)
        local headers = ngx.req.get_headers()
        -- 遍历请求头
        local requestRandom = self.requestRandom
        for key, value in pairs(headers) do
            -- 使用字符串匹配判断以 "xxx-" 开头（忽略大小写）
            local match = string.sub(key, 1, #requestRandom)
            if string.lower(match) == string.lower(requestRandom) then
                matchedHeaders[key] = value
                count = count + 1
            end
        end
    end

    do
        ngx.log(ngx.DEBUG, loggerPrefix, '匹配到请求头: ', json.encode(matchedHeaders))
        if (count > 1) then -- 存在多个请求, 非法
            ngx.log(ngx.DEBUG, loggerPrefix, '存在多个请求头随机数, 非法 !')
            return false
        end

        return self:compareRandom(redisClient, uri, params.address, matchedHeaders)
    end
end

-- 比较请求随机数是否一致
function Main:compareRandom(redisClient, uri, address, matchedHeaders)
    local value
    local key

    do
        -- 从 redis 中获取 以 key- 开头的值
        local keys = redisClient:getKeys(address .. '-random-')
        -- redis 中未存储随机数, 校验通过
        if not keys or #keys == 0 then
            ngx.log(ngx.DEBUG, loggerPrefix, '未设置过请求随机数, 等待请求完成后设置 !')
            redisClient:close()
            return true
        end

        -- 通过 url 和 参数 查找是否有匹配的结果
        local v = self:getRedisRandom(redisClient, uri, keys) or {}
        if Utils.isObjectNull(v) then -- 没有匹配, 则未存储
            ngx.log(ngx.DEBUG, loggerPrefix, '未设置过请求随机数, 等待请求完成后设置 !')
            redisClient:close()
            return true
        end

        value = v.value or {}
        if Utils.isObjectNull(value) then
            ngx.log(ngx.DEBUG, loggerPrefix, '未设置过请求随机数, 等待请求完成后设置 !')
            redisClient:close()
            return true
        end

        key = v.key
    end


    do
        -- 匹配通过
        ngx.log(ngx.DEBUG, loggerPrefix, '找到请求: ', json.encode(value))
        ngx.log(ngx.DEBUG, loggerPrefix, '找到请求 Redis 的 key: ', key)
        local flag = false
        if not matchedHeaders then
            matchedHeaders = {}
        end

        for i, v in pairs(matchedHeaders) do
            -- 匹配 key 和 random
            ngx.log(ngx.DEBUG, loggerPrefix, '请求头中的随机数 key: ', i)
            ngx.log(ngx.DEBUG, loggerPrefix, '请求头中的随机数 value(不区分大小写): ', string.lower(v))
            if (string.lower(i) == string.lower(value.key) and v == value.random) then
                flag =  true
            end
        end

        if (flag) then
            ngx.log(ngx.DEBUG, loggerPrefix, '请求随机数校验通过 !')
            -- 删除旧的 key
            redisClient:del(key)
            redisClient:close()
            return true
        end
    end

    ngx.log(ngx.DEBUG, loggerPrefix, '请求随机数校验未通过, 非法请求 !')
    redisClient:close()
    return false
end

-- 获取 redis 中的请求随机数
function Main:getRedisRandom(redisClient, uri, keys)
    ngx.log(ngx.DEBUG, loggerPrefix, 'keys: ', json.encode(keys))

    for _, k in ipairs(keys) do
        local v = redisClient:get(k)
        -- 没有请求参数
        if Utils.isObjectNull(self.args) then
            if v and uri == v.uri then
                return {value = v, key = k}
            end
        end

        -- 比较参数是否一致
        local isSame = Utils.compareTables(self.args, v.params or {})
        if isSame and v.uri == uri then
            return {value = v, key = k}
        end
    end

    return nil
end

-- 穿透
function Main:penetrate()
    local urls = self:divideUri()
    local xmlDir = self.config.rootDir .. '/' .. urls.projectName .. '/' .. self.config.xmlDir

    do
        -- logs
        ngx.log(ngx.DEBUG, loggerPrefix, 'uri:', self.uri)
        ngx.log(ngx.DEBUG, loggerPrefix, '请求参数:', json.encode(self.args))
        ngx.log(ngx.DEBUG, loggerPrefix, 'config 配置:', json.encode(self.config))

        if not self:validate(urls, xmlDir) then
            ngx.exit(ngx.HTTP_OK)
            return
        end
    end

    local params
    do
        -- 解析 xml
        local parser = XmlParser:new(xmlDir, self.config)
        params = parser:parse(urls.url)
        if not params then
            errorResult.error.reason = '解析数据失败'
            return errorResult
        end

        ngx.log(ngx.DEBUG, loggerPrefix, '获取到 config 配置:', json.encode(params))
        ngx.log(ngx.DEBUG, loggerPrefix, '缓存时间: ', self.cacheTime)

        -- 校验请求随机数, 查看是否为非法请求
        if not self:validateRequestRandom(params, urls.url) then
            errorResult.error.reason = '非法请求'
            return errorResult
        end
    end

    do
        -- 发送请求
        ngx.log(ngx.DEBUG, loggerPrefix, 'uri: ', urls.url)

        -- 非登录和登录请求才从缓存中获取数据
        if params.type ~= 1 and params.type ~= 2 then
            local cache = Cache:new(self.cacheTime, self.config.redis)
            local response = cache:get(params.address, urls.url, self.args)
            if response then
                -- 重新生成随机数
                self:setRequestRandom(params.address, urls.url)
                return response
            end
        end

        local request = Request:new(params, self.args, urls.url, self.config.redis or {}, self.config or {})
        local result = request:send(self.headers)
        if not result then
            errorResult.error.reason = '发送请求失败'
            return errorResult
        end

        return self:getResponse(request, result, params, urls)
    end
end

-- 处理登录返回结果
function Main:handleLogin(result, urls, params, token, tokenName, localTokenName)
    local data = result.data
    if data then
        ngx.log(ngx.DEBUG, loggerPrefix, '请求返回值: ', json.encode(data))
        ngx.log(ngx.DEBUG, loggerPrefix, 'tokenName: ', tokenName)

        -- 存在 redis 中
        local redisClient = Redis:new(self.config.redis)

        -- 获取真实 token, 存入 redis 中
        if Utils.isNull(tokenName) then
            token  = Utils.generateUuid()
            ngx.log(ngx.DEBUG, loggerPrefix, '未找到 token, 重新生成新的 token: ', token)
        else
            -- 从返回值中取 token， 如果没有从 header 头中取
            token = data[tokenName]
            if Utils.isNull(token) then
                ngx.log(ngx.DEBUG, loggerPrefix, '未获取到返回的 token, 直接取名字叫 token 的值 .')
                token = data['token']
                if Utils.isNull(token) then
                    ngx.log(ngx.DEBUG, loggerPrefix, '未获取到名字叫 token 的值, 从 response headers 中获取 .')
                    local resHeaders = result.headers or {}
                    token = resHeaders[tokenName]
                    if Utils.isNull(token) then
                        ngx.log(ngx.DEBUG, loggerPrefix, '未获取到 token .')
                    end
                else
                    tokenName = 'token'
                end
            end

            ngx.log(ngx.DEBUG, loggerPrefix, '获取返回的 token: ', token)
        end

        if Utils.isNull(token) then
            ngx.log(ngx.DEBUG, loggerPrefix, '未找到请求返回的 token, 不存储 token .')
            return {
                code = result.code,
                data = result.data or {},
                error = {},
                extendData = result.extendData or {}
            }
        end

        -- 生成一串 uuid
        local outputToken = Utils.generateUuid()

        -- 存数据
        local opts = {
            host = params.protocol .. '://' .. params.host,
            envProperty = params.address, -- 所属环境配置
            projectName = urls.projectName, -- 项目名称
            realToken = token, -- 用本地 token 换真实 token
            localToken = outputToken, -- 本地通信 token
            time = os.date("%Y%m%d%H%M%S", os.time()) --存储时间
        }

        ngx.log(ngx.DEBUG, loggerPrefix, '存入到 redis 的值: ', json.encode(opts))
        redisClient:del(params.address)
        redisClient:set(params.address, json.encode(opts))
        redisClient:close()

        ngx.header[localTokenName] = opts.localToken -- 设置响应头
        local resultData = result.data or {}
        resultData[localTokenName] = opts.localToken -- 设置返回结果包括 token
        resultData[tokenName] = nil -- 删除真实 token

        return {
            code = result.code,
            data = resultData,
            error = {},
            extendData = result.extendData or {}
        }
    end
end

-- 设置请求随机数
function Main:setRequestRandom(address, uri)
    -- 设置影响头, 生成随机数
    local random = Utils.getEncryptionKey(uri) .. '-' .. tostring(os.time())
    ngx.log(ngx.ERR, loggerPrefix, '生成请求随机数: ', random)
    local uuid = Utils.generateUuid()
    ngx.header[self.requestRandom .. uuid] = random -- 设置响应头

    local redisClient = Redis:new(self.config.redis)
    if not redisClient then
        return nil
    end

    local opts = {
        random = random, -- 随机数
        address = address,
        uri = uri,
        uuid = uuid,
        key = self.requestRandom .. uuid,
        params = self.args,
        time = os.date("%Y%m%d%H%M%S", os.time())
    }

    redisClient:del(address .. '-random-' .. random)
    redisClient:psetex(address .. '-random-' .. random, json.encode(opts), EXPIRE_TIME) -- 1天后过期
    redisClient:close()
end

-- 解析返回值
function Main:getResponse(request, result, params, urls)
    local token
    local success = result.code == '0' or result.code == 0 or result.code == 200

    -- 登录
    if params.type == 1 then
        ngx.log(ngx.DEBUG, loggerPrefix, 'handle login ...')
        -- 根据 tokenName 获取 token
        local tokenName = params.tokenName
        local localTokenName = params.localTokenName
        if Utils.isNull(tokenName) then
            ngx.log(ngx.ERR, loggerPrefix, urls.projectName ..' 中 tokenName is nil .')
            errorResult.error.reason = '发送请求失败'
            return errorResult
        end

        if (success) then
            return self:handleLogin(result, urls, params, token, tokenName, localTokenName)
        end
    elseif params.type == 2 then -- 登出
        -- 清空 redis 中的 值
        if (success) then
            request:operateLogout(self.headers)
        end
    end

    -- 设置请求随机数
    if params.type ~= 1 and params.type ~= 2 then
        self:setRequestRandom(params.address, urls.url)
    end

    local code = result.code
    if type(code) == 'string' then
        code = tonumber(code)
    end

    -- 存储缓存
    local data = {
        code = code,
        data = result.data or {},
        error = result.error,
        extendData = result.extendData or {}
    }

    if data.code == 0 and params.type ~= 1 and params.type ~= 2 then
        ngx.log(ngx.DEBUG, loggerPrefix, '开始缓存数据 ...')
        ngx.log(ngx.DEBUG, loggerPrefix, '缓存时间: ', self.cacheTime)
        local cache = Cache:new(self.cacheTime, self.config.redis)
        cache:set(params.address, data, urls.url, self.args)
        ngx.log(ngx.DEBUG, loggerPrefix, '缓存数据成功 !')
    end

    return data
end

return Main