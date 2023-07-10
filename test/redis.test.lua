--[[
    location /testRedis {
        default_type 'application/json'; #返回Json文本
        content_by_lua_file /home/nginx-code/test/redis.test.lua;
    }
    测试: curl -X GET https://localhost:9999/testRedis
--]]

local Redis = require('modules.redis.index')

-- redis 配置
local REDIS_CONFIG = {
    host = '127.0.0.1',
    port = 6379,
    auth = '23456774'
}

local client = Redis:new(REDIS_CONFIG)
client:set('dog', 'an animal')
local value = client:get('dog')
ngx.say(value)
ngx.exit(ngx.HTTP_OK) -- 200


