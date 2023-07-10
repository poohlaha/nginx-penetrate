--[[
   解析项目下的 config.xml 和 module.xml 文件
--]]
local Utils = require('modules.utils.index')
local Xml = require('modules.xml.index')

local loggerPrefix = '[Nginx Lua Xml Parser]'

local XmlParser = {}
XmlParser.__index = XmlParser

function XmlParser:new(dir, config)
    self.dir = dir
    self.config = config
    return self
end

-- 读取 xml 数据
function XmlParser:getXmlData(filePath)
    if not filePath then
        ngx.log(ngx.DEBUG, loggerPrefix, 'filePath is nil .')
        return nil
    end

    ngx.log(ngx.DEBUG, loggerPrefix, '解析 xml:', filePath)

    local xmlHandler = Xml:new(filePath)
    local xmlData = xmlHandler:read()

    if not xmlData then
        ngx.log(ngx.ERR, loggerPrefix, 'XML date is nil .')
        return nil
    end

    -- ngx.log(ngx.DEBUG, loggerPrefix, json.encode(xmlData))
    return xmlData
end

-- 获取模块配置
function XmlParser:getModuleApis(xmlModule)
    local apis = xmlModule.apis
    if not apis then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlModule apis is nil .')
        return nil
    end

    local api = apis.api
    local attr = apis._attr
    if not api then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlModule api is nil .')
        return nil
    end

    if not attr then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlModule attr is nil .')
        return nil
    end

    local environment = attr.environment
    if Utils.isNull(environment) then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlModule environment is nil .')
        return nil
    end

    return {
        environment = environment,
        modules = api
    }
end

-- 获取当前环境配置
function XmlParser:getEnvironmentConfig(xmlConfig, environment)
    local configs = xmlConfig.configs
    if not configs then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlConfig configs is nil .')
        return nil
    end

    local config = configs.config
    if not config then
        ngx.log(ngx.ERR, loggerPrefix, 'xmlConfig config is nil .')
        return nil
    end

    local environmentConfig
    for _, v in pairs(config) do
        local attr = v._attr
        if attr then
            if attr.environment == environment then
                environmentConfig = v.properties
                break
            end
        end
    end

    if not environmentConfig then
        ngx.log(ngx.ERR, loggerPrefix, 'environment config is nil .')
        return nil
    end

    return environmentConfig
end

-- 获取完整的 url
function XmlParser:getWholeUrl(url, environmentConfig, moduleConfig)
    local modules = moduleConfig.modules
    local module
    local environment

    do
        for _, v in pairs(modules) do
            if (v.uri == url) then
                module = v
            end
        end

        if not module then
            ngx.log(ngx.ERR, loggerPrefix, '未找到 module .')
            return nil
        end

        if not module.destination then
            ngx.log(ngx.ERR, loggerPrefix, '未找到 module 下的 destination 节点 .')
            return nil
        end
    end

    -- 拼装 url
    do
        local config
        for _, v in pairs(environmentConfig) do
            local attr = v._attr
            if attr then
                if (attr.name == module.address) then
                    config = v.property
                end
            end
        end

        if not config then
            ngx.log(ngx.ERR, loggerPrefix, '未找到 config')
            return nil
        end

        environment = {}
        for _, v in pairs(config) do
            local attr = v._attr
            local value = attr.value
            if attr then
                -- timeout
                if (attr.name == 'timeout') then
                    local timeout = 10000 -- 默认 10 s
                    if not Utils.isNull(value) then
                        timeout = tonumber(value)
                    end

                    environment.timeout = timeout
                end

                -- host
                if (attr.name == 'host') then
                    if not Utils.isNull(value) then
                        environment.host = value
                    end
                end

                -- protocol
                if (attr.name == 'protocol') then
                    if not Utils.isNull(value) then
                        environment.protocol = value
                    end
                end

                -- localTokenName
                if (attr.name == 'localTokenName') then
                    if Utils.isNull(value) then
                        environment.localTokenName = self.config.localTokenName
                    else
                        environment.localTokenName = value
                    end
                end

                -- tokenName
                if (attr.name == 'tokenName') then
                    if Utils.isNull(value) then
                        environment.tokenName = self.config.tokenName
                    else
                        environment.tokenName = value
                    end
                end
            end
        end
    end

    local moduleType = module.type
    do
        if Utils.isNull(moduleType) then
            moduleType = 0
        end

        if type(moduleType) == 'string' then
            moduleType = tonumber(moduleType)
        end
    end

    return {
        auth = module.auth ~= '1', -- 默认为鉴权, 为 1 则跳过鉴权
        address = module.address,
        type = moduleType,
        protocol = environment.protocol,
        host = environment.host,
        uri = module.destination.uri,
        url = (environment.protocol or '') .. '://' .. (environment.host or '') .. (module.destination.uri or ''),
        method = module.destination.method or 'POST',
        header = module.destination.header or '',
        timeout = environment.timeout,
        localTokenName = environment.localTokenName,
        tokenName = environment.tokenName
    }
end

-- 解析
function XmlParser:parse(url)
    ngx.log(ngx.DEBUG, loggerPrefix, 'XML 目录:', self.dir)

    do
        if not url then
            ngx.log(ngx.DEBUG, loggerPrefix, 'url is nil .')
            return nil
        end

        if not self.dir then
            ngx.log(ngx.DEBUG, loggerPrefix, 'dir is nil .')
            return nil
        end
    end

    do
        local xmlConfig = self:getXmlData(self.dir .. '/config.xml')
        local xmlModule = self:getXmlData(self.dir .. '/module.xml')

        if (not xmlConfig or not xmlModule) then
            return nil
        end

        local moduleConfig = self:getModuleApis(xmlModule)
        if not moduleConfig then
            return nil
        end

        local environmentConfig = self:getEnvironmentConfig(xmlConfig, moduleConfig.environment)
        if not environmentConfig then
            ngx.log(ngx.DEBUG, loggerPrefix, 'environmentConfig is nil .')
            return nil
        end

        return self:getWholeUrl(url, environmentConfig, moduleConfig)
    end
end

return XmlParser