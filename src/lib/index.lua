--[[
   穿透框架主入口
--]]
local json = require('dkjson')
local Main = require('main.index')
local loggerPrefix = '[Nginx Lua Penetrate]'

-- 全局异常
local function handleError(err)
    if not err then
        return
    end

    ngx.log(ngx.ERR, 'Global error handler: ', err)
    -- 返回错误响应给客户端
    local result = {
        code = ngx.HTTP_INTERNAL_SERVER_ERROR,
        error = {
            reason = '未知异常 !'
        },
        data = {},
        extendData = {}, -- 额外的数据
    }
    ngx.status = ngx.HTTP_INTERNAL_SERVER_ERROR
    ngx.print(json.encode(result))
    ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
end

ngx.log(ngx.DEBUG, loggerPrefix, '================== begin Penetrate ==============')

pcall(handleError)

local handler = Main:new()
local result = handler:penetrate()
ngx.print(json.encode(result))

ngx.log(ngx.DEBUG, loggerPrefix, '================== end Penetrate ==============')
ngx.exit(ngx.HTTP_OK)
