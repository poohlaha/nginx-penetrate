--[[
    调用 OpenResty 的 resty.http 发送 https 请求
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
--]]
local http = require('resty.http')
local json = require('dkjson')
local Utils = require('modules.utils.index')

local loggerPrefix = '[Nginx Lua Https]'

local DEFAULT_METHOD = 'POST'

local Https = {}
Https.__index = Https

--[[
    opts: {
        url = '', -- url
        body = '', -- 请求参数
        method = '', -- method
        headers = {}, -- headers
        timeout = 10000, -- 默认为 10 s
        useSslVerify = false, -- 是否启用ssl证书
        sslCert = '', -- 如果 useSslVerify = true, 则有需要可以填写证书地址
        sslKey = ''-- 如果 useSslVerify = true, 则有需要可以填写证书地址
    }
--]]
function Https:new(opts)
    self.url = opts.url
    self.body = opts.body
    self.method = opts.method or DEFAULT_METHOD
    self.headers = opts.headers
    self.timeout = opts.timeout
    self.useSslVerify = opts.useSslVerify
    self.sslCert = opts.sslCert
    self.sslKey = opts.sslKey
    return self
end

-- 发送语法
function Https:send()
    do
        if Utils.isNull(self.url) then
            ngx.log(ngx.ERR, loggerPrefix, 'url is nil.')
            return {
                error = 'url is nil .',
                code = 500
            }
        end
    end

    do
        local headers = self.headers
        local body = self.body

        if not body then
            body = {}
        end

        if not headers then
            headers = {}
        end

        local params = {
            method = self.method,
            keepalive_timeout = self.timeout
        }

        if not headers['Content-Type'] then
            headers['Content-Type'] = 'application/json;charset=UTF-8'
        end

        if string.upper(self.method) == 'POST' then
            params.body = json.encode(body) 
            if not headers['Content-Length'] then
                headers['Content-Length'] = #params.body
            end
        elseif string.upper(self.method) == 'GET' then
            params.query = body
        end

        -- headers
        params.headers = headers

        if not self.useSslVerify then
            params.ssl_verify = false
            params.ssl_verify_depth = 0 -- 将 ssl_verify_depth 设置为 0，以避免深度验证
        else
            params.ssl_cert = self.sslCert
            params.ssl_key = self.sslKey
            params.ssl_verify_depth = 1
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'request url: ', self.url)
        ngx.log(ngx.DEBUG, loggerPrefix, 'request headers: ', json.encode(headers))
        ngx.log(ngx.DEBUG, loggerPrefix, 'request params: ', json.encode(params))
        ngx.log(ngx.DEBUG, loggerPrefix, 'request use ssl: ', params.ssl_verify)

        local client = http.new() -- 初始化
        local res, err = client:request_uri(self.url, params)

        if not res then
            ngx.log(ngx.ERR, loggerPrefix, 'request failed: ', err)
            return {
                error = 'request failed: ' .. err,
                code = 500
            }
        end

        -- 处理返回
        do
            -- res: headers, status, body, reason
            if res.status ~= 200 then
                ngx.log(ngx.ERR, loggerPrefix, 'request failed !')
                ngx.log(ngx.ERR, loggerPrefix, 'response status: ', res.status)
                ngx.log(ngx.ERR, loggerPrefix, 'response reason: ', res.reason)
                return {
                    error = 'request failed, response status:' .. res.status .. ' reason: ' .. res.reason,
                    code = 500
                }
            end

            ngx.log(ngx.DEBUG, loggerPrefix, 'request response: ', json.encode(res.body))
            local obj, pos, error = json.decode(res.body, 1, nil)
            if err then
                return {
                    error = 'get response body error, ' .. error,
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
                            options.code = 0
                        end
                    end
                end

                return options
            end
        end
    end
end

return Https

