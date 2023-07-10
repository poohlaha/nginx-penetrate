# Centos 环境安装

## OpenResty
  - 官方文档: https://openresty.org/en/linux-packages.html#centos
  - `github` 地址: https://github.com/openresty

### 目录
   - 静态目录: `/home/www`
   - `lua` 代码: `/home/nginx-code`
   - `nginx` logs: `/home/nginx-logs`
   - 第三方库(非 `opm` 安装的包): `/home/nginx-resty/lib/lua`
   - `openresty` 安装目录: `/usr/local/openresty`
   - `nginx` `conf` 目录: `/usr/local/openresty/nginx/conf/`
   - 证书目录: `/home/nginx-cert`

### nginx配置
   - nginx.conf
   ```shell
    # nginx.conf
    http {
     ...
     
     include /usr/local/openresty/nginx/conf/lua.conf;  # lua.conf 地址(添加 lua.conf 文件)
     lua_package_path '/home/luarocks/luarocks-3.8.0/lua_modules/share/lua/5.1/?.lua;/home/nginx-resty/lib/lua/?.lua;/home/nginx-code/?.lua;;'; # 指定地址(包括第三方插件包地址)
     lua_package_cpath '/home/luarocks/luarocks-3.8.0/lua_modules/lib/lua/5.1/?.so;/home/nginx-resty/lib/lua/?.so;/home/nginx-code/?.so;;'; # 指定地址
     lua_code_cache off; # 热部署, 每次修改 lua 文件, 不用重新加载部署
     lua_need_request_body on; # 开启以获取 post 请求参数
     
     ...
     
     server {
        listen       8888;  # 端口
        server_name  localhost;

        access_log  /home/nginx-logs/access.log; # 日志 
        error_log  /home/nginx-logs/error.log; # 错误日志

        #允许跨域
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Access-Control-Allow-Methods' '*';
        add_header 'Access-Control-Allow-Headers' '*';

        root /home/www;  # 指定 www 地址
        ...
        
        location / {
            root   /home/www;
            index  index.html index.htm;
        }

        location /favicon.ico {
            root /home/www;
        }
        
        ...
        
        # 示例: 配置 chat
        location /chat {
            index  index.html index.htm;
            # alias /home/www/chat;
            try_files $uri $uri/ /chat/index.html; # 此处设为相对地址，解决 404 问题
        }
        
        # 转发请求到 443 下
        location /chat/v1 {
            # rewrite  ^/chat/?(.*)$ /$1 break;
            add_header Access-Control-Allow-Headers  $http_access_control_request_headers;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header REMOTE-HOST $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_pass https://localhost/chat/v1; # 转发地址

            if ($request_method = 'OPTIONS') {
                return 200;
            }
        }   
        
        ...
        
     }
     
     ...
    }
   ```
  
   - lua.conf
   ```shell
    # lua.conf
    server {
        listen       9999;
        server_name  localhost;
        #把http的域名请求转成https
        rewrite ^(.*)$ https://$host$1 permanent; 
    }

    server {
        listen       443 ssl;
        server_name  localhost;
    
        access_log  /home/nginx-logs/lua_access.log; # 
        error_log  /home/nginx-logs/lua_error.log debug;
    
        #允许跨域
        add_header 'Access-Control-Allow-Origin' '*';
        add_header 'Access-Control-Allow-Credentials' 'true';
        add_header 'Access-Control-Allow-Methods' '*';
        add_header 'Access-Control-Allow-Headers' '*';
    
        # 配置证书
        ssl_session_timeout 5m;
        # ssl_protocols   TLSv1 TLSv1.1 TLSv1.2;
        ssl_certificate     /home/nginx-cert/server.pem;
        ssl_certificate_key /home/nginx-cert/server.key;
        lua_ssl_verify_depth 2;
        lua_ssl_trusted_certificate '/home/nginx-cert/server.pem';
        
        root '/home/nginx-code'; # 指定静态文件目录
        set $template_location "/templates"; # first match ngx location, 相对于 root 配置的地址( / 不能少)
        set $template_root "/usr/local/openResty/templates"; # then match root read file
    
        resolver 223.5.5.5 223.6.6.6 1.2.4.8 114.114.114.114 8.8.8.8 valid=3600s;
    
        # 示例 1
        location /testLua {
            default_type 'text/plain';
            # content_by_lua 'ngx.say("hello, lua")';
            content_by_lua_block {
                ngx.say("ngx.req.get_method: ", ngx.req.get_method(), "<br/>")
                ngx.say("hello, lua")
            }
        }
    
        # 示例 2
        location /testHttps {
            default_type 'application/json'; #返回Json文本
            content_by_lua_file /home/nginx-code/https.test.lua;
        }
    
        # 示例 3
        location /testCache {
            default_type 'text/html';
            content_by_lua_block {
                require('nginx-cache/cache').go()
            }
        }
        
      ...
   }
   ```

### 安装
   1. 添加 `OpenResty` 官方仓库<br/>
      打开终端并以 `root` 用户身份执行以下命令:
   ```shell
      yum install yum-utils -y
      yum-config-manager --add-repo https://openresty.org/package/centos/openresty.repo
   ```

   2. 安装 `OpenResty` <br/>
      执行以下命令安装 `OpenResty`:
   ```shell
      yum install openresty -y
   ```

   3. 启动 `OpenResty` <br/>
      安装完成后，可以使用以下命令启动 `OpenResty`:
   ```shell
      systemctl start openresty
   ```
   ps: 如果您想要在系统启动时自动启动 `OpenResty`，请执行以下命令:
   ```shell
      systemctl enable openresty
   ```

   4. 验证 `OpenResty` 是否成功安装<br/>
      执行以下命令验证 `OpenResty` 是否已成功安装:
   ```shell
      openresty -v
   ```

   5. 把 `nginx` 添加到环境变量(`~/.bashrc` 或 `/etc/profile`, 使用 `source` 使其生效)
   ```shell
      export PATH=$PATH:/usr/local/openresty/nginx/sbin
   ```

### 模块安装

   - 使用 `OPM` 安装模块
     * 检查 `OPM` 是否已安装<br/>
       首先，请检查您的系统上是否已经安装了OPM。可以通过运行以下命令来检查:
       ```shell
          opm --version
       ```

     * 如果您的系统上没有安装 `OPM`，您可以通过以下命令来安装它:
       ```shell
          sudo yum install -y openresty-opm
       ```
       
     * 安装完OPM之后，可以使用以下命令来安装 `xxx` 模块:
       ```shell
          sudo opm get xxx/xxx
       ```
     此命令将从 `OpenResty` 官方的 `OPM` 仓库中获取 `xxx` 模块并安装它。

     * 验证模块是否安装成功<br/>
       安装完成后，可以使用以下命令来验证 `xxx` 模块是否已经成功安装：
       ```shell
          sudo opm list | grep xxx
       ```
       如果输出结果中包含 `xxx`，则说明模块已经安装成功。

   - 模块
   1. lua-resty-http 
      `github` 地址: https://github.com/ledgetech/lua-resty-http
      ```shell
         sudo opm get ledgetech/lua-resty-http
      ```

   2. lua-resty-core(该库在 `OpenResty` `1.15.8.1` 中默认自动加载, 不需要添加, 删除)<br/>
      `github` 地址: https://github.com/openresty/lua-resty-core
      ```shell
         sudo opm get openresty/lua-resty-core
      ```
      
   3. lua-resty-mysql<br/>
      `github` 地址: https://github.com/openresty/lua-resty-mysql
      ```shell
         sudo opm get openresty/lua-resty-mysql
      ```
      
      PS: 因为 `mysql` 需要 `sha256`, 需要安装 `lua-resty-string` 安装包。

   4. lua-resty-string<br/>
      `github` 地址: https://github.com/openresty/lua-resty-string
      ```shell
         sudo opm get openresty/lua-resty-string
      ```
      
   4. lua-resty-template<br/>
      `github` 地址: https://github.com/bungle/lua-resty-template
      ```shell
         sudo opm get bungle/lua-resty-template
      ```    
      
      需要在 lua.conf 中设置模板路径:
      ```shell
         root '/home/nginx-code'; # 指定静态文件目录
         set $template_location "/templates"; # first match ngx location, 相对于 root 配置的地址( / 不能少)
         set $template_root "/usr/local/openResty/templates"; # then match root read file
      ``` 

   5. dkjson<br/>
      地址: http://dkolf.de/src/dkjson-lua.fsl/home <br/>
      目录: /home/nginx-resty/lib/lua/
      ```shell
         cd /home/nginx-resty/lib/lua
         wget http://dkolf.de/src/dkjson-lua.fsl/raw/dkjson.lua?name=16cbc26080996d9da827df42cb0844a25518eeb3  -O dkjson.lua
      ```

   6. itn12<br/>
      需要先通过 `luarocks` 安装 `luasocket`。<br/>
      `ltn12` 是 `LuaSocket` 库中的一个模块，用于在 `Lua` 中处理数据流。如果 `OpenResty` 中没有安装 `LuaSocket` 库，需要先安装该库才能使用 `ltn12`。
      ```shell
         sudo luarocks install luasocket
         
         # 在 nginx.conf 中修改 `lua_package_path` 和 `lua_package_cpath`,
         lua_package_path "/home/luarocks/luarocks-3.8.0/lua_modules/share/lua/5.1/?.lua;;";
         lua_package_cpath "/home/luarocks/luarocks-3.8.0/lua_modules/lib/lua/5.1/?.so;;";
      ```

### luarocks
   `luarocks` 是 `Lua` 的包管理器，可以用来管理 Lua 库的安装和升级。要在 `CentOS 7` 中安装 `luarocks`，可以使用以下步骤:

   1. 安装依赖项<br/>
      在终端中执行以下命令，安装 `luarocks` 的依赖项:
      ```shell
         sudo yum install readline-devel openssl-devel gcc
      ```

   2. 下载安装包<br/>
      下载目录在 `/home/luarocks/` 下, 在终端中执行以下命令，下载 `luarocks` 的源码包:
      ```shell
         wget https://luarocks.org/releases/luarocks-3.8.0.tar.gz 
      ```

   3. 解压安装包<br/>
      在终端中执行以下命令，解压下载的 `luarocks` 安装包:
      ```shell
         tar zxpf luarocks-3.8.0.tar.gz 
      ```

   4. 编译安装<br/>
      在终端中执行以下命令，编译并安装 `luarocks`:
      ```shell
         cd /home/luarocks/luarocks-3.8.0
         ./configure --prefix=/usr/local/openresty/luajit \
            --with-lua=/usr/local/openresty/luajit \
            --with-lua-include=/usr/local/openresty/luajit/include/luajit-2.1
         make
         sudo make install
      ```

   5. 设置环境变量
      ```shell
        # 最后一行添加:
        export PATH=$PATH:/usr/local/openresty/luajit/bin
        source ~/.bashrc 或 source /etc/profile
        
        # 添加 LUA_INCLUDE_DIR 环境变量
        export LUA_INCLUDE_DIR=/usr/local/openresty/luajit/include/luajit-2.1
      ```


   6. 验证安装<br/>
      在终端中执行以下命令，验证 `luarocks` 是否成功安装: <br/>
      目录为: `/usr/local/openresty/luajit/bin`
      ```shell
         luarocks --version
      ```
      输出:
      ```shell
         /usr/local/openresty/luajit/bin/luarocks 3.8.0
         LuaRocks main command-line interface
      ```
      则表示 `luarocks` 已经成功安装。

### unzip
   ```shell
   sudo yum install -y unzip
   ```

### 证书
   发送 `https` 请求需要添加证书<br/>
   `lua.conf` 中添加证书, 证书存放在 `/home/nginx-cert` 目录下
   ```shell
   # lua.conf
    server {
    listen       443 ssl;
    
        ...
    
        # 配置证书
        ssl_session_timeout 5m;
        ssl_certificate     /home/nginx-cert/server.pem; # 证书目录 /home/nginx-cert
        ssl_certificate_key /home/nginx-cert/server.key; # 证书目录 /home/nginx-cert
        ssl_prefer_server_ciphers on;
    
        ...
    }
   ```

## Redis
   1. 安装Redis软件包:
   ```shell
      sudo yum install redis
   ```

   2. 修改密码, 打开Redis配置文件:
   ```shell
      sudo vi /etc/redis.conf
   ```

   3. 在配置文件中找到以下行:
   ```shell
      # requirepass foobared
   ```
   将其修改为：
   ```shell
      requirepass your_password
   ```
   将 "your_password" 替换为您想要设置的实际密码，并保存并关闭文件。

   4. 启动Redis服务:
   ```shell
      sudo systemctl start redis
   ```

   5. 设置Redis开机自启动:
   ```shell
      sudo systemctl enable redis
   ```

   6. 重新启动Redis服务:
   ```shell
     sudo systemctl restart redis
   ```
ps: 在线密码生成器: http://mima.wiicha.com/?cate=1234&length=16&num=10