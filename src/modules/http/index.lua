--[[
    调用 OpenResty 的 resty.http 发送 http 请求
    lua-resty-http:
        地址: https://github.com/ledgetech/lua-resty-http/tree/master
        安装:
            - 使用 make: make install PREFIX=/home/nginx-resty
            - 使用 opm: opm get ledgetech/lua-resty-http

    dkjson:
        地址: http://dkolf.de/src/dkjson-lua.fsl/home
        安装:
            ```
                cd /home/nginx-resty/lib/lua
                wget http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3  -O dkjson.lua
            ```
    测试: curl -X GET http://localhost:9999/testHttp
--]]
local http = require('resty.http')
local json = require ('dkjson')
local Utils = require('modules.utils.index')

local loggerPrefix = '[Nginx Lua Http]'

local DEFAULT_METHOD = 'POST'

local Http = {}
Http.__index = Http

--[[
    opts: {
        url: '', // 访问路径
        opts: {
            method = '', // 默认为 POST
            headers = {}, // headers
            keepalive_timeout = 10000, // 默认为 10s
        }
    }
--]]
-- 传递的参数放在 url 上直接拼接
function Http:new(url, opts)
    self.url = url
    self.opts = opts
    return self
end

-- validate url or method
function Http:validate()
    -- url
    local url = self.url or nil
    if Utils.isNull(url) then
        ngx.log(ngx.ERR, loggerPrefix, 'url is nil .')
        return false
    end

   return true
end

function Http:send()
    do
        local flag = self:validate()
        if not flag then
            return {
                error = 'url is nil .',
                code = 500
            }
        end
    end

    do
        -- opts
        local opts = self.opts
        if not opts then
            opts = {}
        end

        opts.method = opts.method or DEFAULT_METHOD
        opts.keepalive_timeout = opts.keepalive_timeout
        opts.sslVerify = false

        do
            local headers = opts.headers
            if not headers then
                headers = {}
            end

            if not headers['Content-Type'] then
                headers['Content-Type'] = 'application/json;charset=UTF-8'
            end

            opts.headers = headers
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'opts url: ', self.url)
        ngx.log(ngx.DEBUG, loggerPrefix, 'opts method: ', opts.method)
        ngx.log(ngx.DEBUG, loggerPrefix, 'opts headers: ', json.encode(opts.headers))
        ngx.log(ngx.DEBUG, loggerPrefix, 'opts keepalive_timeout: ', opts.keepalive_timeout) -- to string

        -- http
        local client = http.new()
        local res, err = client:request_uri(self.url, opts)

        if not res then
            ngx.log(ngx.ERR, loggerPrefix, 'request failed: ', err)
            return {
                error = 'request failed: ' .. err,
                code = 500
            }
        end

        if 200 ~= res.status then
            ngx.log(ngx.ERR, loggerPrefix, 'request failed !')
            ngx.log(ngx.ERR, loggerPrefix, 'response status: ', res.status)
            ngx.log(ngx.ERR, loggerPrefix, 'response reason: ', res.reason)
            return {
                error = 'request failed, response status:' .. res.status .. ' reason: ' .. res.reason,
                code = 500
            }
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'request response: ', json.encode(res.body))

        -- 解析数据
        local obj, pos, err = json.decode(res.body, 1, nil)
        if err then
            return {
                error = 'get response body error, ' .. err,
                code = 500
            }
        end

        if not obj then
            return {
                error = '未返回数据 !',
                code = 500
            }
        end

        do
            local code = obj.code
            if type(code) == 'string' then
                code = tonumber(obj.code)
            end

            local options = {
                code = obj.code,
                data = obj.data,
                extendData = obj.extendData
            }

            if (code ~= 0 and code ~= 200) then
                if not options.data then
                    options.error = {
                        reason = obj.reason or obj.errorMsg or obj.errorMessage or obj.codeInfo or '服务器异常, 请稍候再试'
                    }
                else
                    if not options.code then
                        options.code  = 0
                    end
                end
            end

            return options
        end

    end
end

return Http




