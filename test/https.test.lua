--[[
    location /testHttps {
        default_type 'application/json'; #返回Json文本
        content_by_lua_file /home/nginx-code/test/https.test.lua;
    }

    测试: curl -X GET http://localhost:9999/testHttps
--]]
local Https = require('modules.https.index')
local client = Https:new({
    url = 'https://example.com/api/getData',
    body = {
        uname = '111'
    },
    method = 'POST',
    useSslVerify = false
})

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
    ngx.say('nothing !')
    ngx.exit(ngx.HTTP_OK) -- 200
end

ngx.say(data.code)
