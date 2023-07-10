--[[
    location /testHttp {
        default_type 'application/json'; #返回Json文本
        content_by_lua_file /home/nginx-code/test/http.test.lua;
    }

    测试: curl -X GET http://localhost:9999/testHttp
--]]

local Http = require('modules.http/index')

local client = Http:new(
        'http://example.com/api/generate',
        {
            method = 'GET',
            headers = {},
            keepalive_timeout = 60000
        }
)

local result = client:send()
ngx.log(ngx.DEBUG, 'result code: ', result.code)
ngx.log(ngx.DEBUG, 'result error: ', result.error)

if result.error then
    ngx.say(result.error)
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR) -- 500
end

local data = result.data
-- no data
if not data then
    ngx.say('')
    ngx.exit(ngx.HTTP_OK) -- 200
end

ngx.say(data.text)



