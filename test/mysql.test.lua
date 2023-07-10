--[[
     location /testMysql {
        default_type 'application/json'; #返回Json文本
        content_by_lua_file /home/nginx-code/test/mysql.test.lua;
    }

    测试: curl -X GET http://localhost:9999/testMysql
--]]

local Mysql = require('modules.database.mysql')
local json = require ("dkjson")

local config = {
    host = '127.0.0.1',
    port = 3306,
    database = 'test',
    user = 'test',
    password = 'test@1234'
}

local client = Mysql:new(config.host, config.port, config.database, config.user, config.password)
if client then
    local ok = client:connect()
    if ok then
        local results = client:query('SELECT * FROM test.info')
        if results then
            ngx.log(ngx.DEBUG, 'results', json.encode(results))
            for _, value in pairs(results) do
                ngx.say(value.name or '')
            end
        end
    end
end
