--[[
    Utils 类
--]]
local restySha256 = require('resty.sha256')
local restyStr = require('resty.string')

local Utils = {}

-- 判断是否为空
function Utils.isNull(val)
    return (val == nil or val == ngx.null or val == "" or val == " ")
end

-- 判断目录是否存在
function Utils.isDirExists(dir)
    if Utils.isNull(dir) then
        return false
    end

    -- 判断目录是否存在，其中>nul和2>nul是将修改重定向到空，否则当目录不存在时，会有错误提
    if not os.execute('cd ' .. '\'' .. dir .. '\' >nul 2>nul') then
        return false
    end

    return true
end

-- 生成 uuid
function Utils.generateUuid()
    local resty_random = require "resty.random"
    local resty_string = require "resty.string"

    local random_bytes = resty_random.bytes(16)
    local hex_string = resty_string.to_hex(random_bytes)

    -- 将 UUID 按照标准格式进行分段
    local uuid = string.format("%s-%s-%s-%s-%s",
            string.sub(hex_string, 1, 8),
            string.sub(hex_string, 9, 12),
            string.sub(hex_string, 13, 16),
            string.sub(hex_string, 17, 20),
            string.sub(hex_string, 21, 32)
    )

    return uuid
end

-- 分割字符串
function Utils.split(str, sep)
    local parts = {}
    local pattern = string.format("([^%s]+)", sep)
    str:gsub(pattern, function(c) parts[#parts + 1] = c end)
    return parts
end

-- 比较两个 json 是否一致
function Utils.compareTables(t1, t2)
    if type(t1) ~= type(t2) then
        return false
    end

    if type(t1) ~= "table" then
        return t1 == t2
    end

    -- 检查表2中是否有表1没有的键
    for k, _ in pairs(t2) do
        if t1[k] == nil then
            return false
        end
    end

    -- 比较表中的每个键值对
    for k, v in pairs(t1) do
        if not Utils.compareTables(v, t2[k]) then
            return false
        end
    end

    return true
end

-- 获取加密的 key
function Utils.getEncryptionKey(value)
    local sha256 = restySha256:new()
    sha256:update(value)
    local digest = sha256:final()
    return restyStr.to_hex(digest)
end

-- 判断 json 是否为空
function Utils.isObjectNull(obj)
    if not obj then
        return true
    end

    if type(obj) == "table" then
        return next(obj) == nil
    end

    return false
end

return Utils