--[[
    使用 xml2lua 读取 .xml 配置文件
    地址: https://github.com/manoelcampos/xml2lua
    安装: luarocks install xml2lua
--]]
local xml2lua = require('xml2lua')
local handler = require("xmlhandler.tree")
local Utils = require('modules.utils.index')

local loggerPrefix = '[Nginx Lua Redis]'

local Xml = {}
Xml.__index = Xml

function Xml:new(filePath)
    self.filePath = filePath
    return self
end

-- 读取数据
function Xml:read()
    do
        if Utils.isNull(self.filePath) then
            ngx.log(ngx.ERR, loggerPrefix, 'filePath is nil .')
            return nil
        end
    end

    local data = ''

    do
        --读取 xml 文件
        local file = io.open(self.filePath, "r")
        data = file:read("*a")
        file:close()
    end

    do
        -- 解析返回结果
        -- ngx.log(ngx.DEBUG, loggerPrefix, 'data: ', data)
        local parser = xml2lua.parser(handler)
        parser:parse(data)
    end

    return handler.root or nil
end

return Xml