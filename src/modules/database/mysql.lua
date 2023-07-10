--[[
  连接 mysql, 需要下载 lua-resty-mysql 安装包
  lua-resty-mysql:
    地址: https://github.com/openresty/lua-resty-mysql
    安装:
         - 使用 make: make install PREFIX=/home/nginx-resty
         - 使用 opm: opm get openresty/lua-resty-mysql

  lua-resty-string:
  因为 mysql 需要 sha256, 需要安装 lua-resty-string 安装包
    地址: https://github.com/openresty/lua-resty-string/tree/master
    安装:
         - 使用 make: make install PREFIX=/home/nginx-resty
         - 使用 opm: opm get openresty/lua-resty-string
--]]
local sql = require('resty.mysql')
local Utils = require('modules.utils.index')

local loggerPrefix = '[Nginx Lua Mysql]'

local Mysql = {}
Mysql.__index = Mysql

function Mysql:new(host, port, database, user, password, charset, maxPacketSize)
    self.host = host
    self.port = port or 3306
    self.database = database
    self.user = user
    self.password = password
    self.charset = charset or 'utf8'
    self.maxPacketSize = maxPacketSize or 1024 * 1024
    return self
end

-- connect
function Mysql:connect()
    -- validate
    do
        if Utils.isNull(self.host)  then
            ngx.log(ngx.ERR, loggerPrefix, 'host is nil .')
            return false
        end

        if Utils.isNull(self.database) then
            ngx.log(ngx.ERR, loggerPrefix, 'database is nil .')
            return false
        end

        if Utils.isNull(self.user) then
            ngx.log(ngx.ERR, loggerPrefix, 'user is nil .')
            return false
        end

        if Utils.isNull(self.password) then
            ngx.log(ngx.ERR, loggerPrefix, 'password is nil .')
            return false
        end
    end

    -- mysql connect
    local db, error = sql:new()
    do
        if not db then
            ngx.log(ngx.ERR, loggerPrefix, 'failed to instantiate mysql: ', error)
            return false
        end
    end

    do
        db:set_timeout(5000) -- 1 sec
        local ok, err, errCode, sqlState = db:connect({
            host = self.host,
            port = self.port,
            database = self.database,
            user = self.user,
            password = self.password,
            charset = self.charset,
            max_packet_size = self.maxPacketSize
        })

        if not ok then
            ngx.log(ngx.ERR, loggerPrefix, 'failed to connect: ', err, ': ', errCode, ' ', sqlState)
            return false
        end

        ngx.log(ngx.DEBUG, loggerPrefix, 'connect to MySQL success !')
        self.db = db
        return true
    end
end

-- query
function Mysql:query(statement)
    -- validate
    do
        if not self.db then
            ngx.log(ngx.ERR, loggerPrefix, 'not connected to MySQL !')
            return nil
        end
    end

    do
        if Utils.isNull(statement) then
            ngx.log(ngx.ERR, loggerPrefix, 'statement is nil .')
            return nil
        end
    end

    do
        local res, err, errCode, sqlState = self.db:query(statement)
        if not res then
            ngx.log(ngx.ERR, loggerPrefix, 'failed to connect: ', err, ': ', errCode, ' ', sqlState)
            return nil
        end

        return res
    end
end

-- close db
function Mysql:close()
    -- validate
    do
        if not self.db then
            ngx.log(ngx.ERR, loggerPrefix, 'not connected to MySQL !')
            return
        end
    end

    do
        local ok, err = self.db:close()
        if not ok then
            ngx.log(ngx.ERR, loggerPrefix, 'failed to close: ', err)
        end
    end
end

return Mysql