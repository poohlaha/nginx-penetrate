# nginx penetrate
  使用 `OpenResty` 来编写 `nginx` 穿透、拦截、限流等操作。

## api 
1. `nginx` 配置<br/>
    可以通过 `$configDir` 来配置 `config.json` 文件地址, 如果不配置，则取默认地址: `/home/nginx-code/config/config.json`。
    ```shell
    # 匹配以 /chat/v1 开头
     location ^~ /chat/v1 {
       default_type 'application/json'; #返回Json文本
       set $configDir '/home/nginx-code/config/config.json; # 设置 config.json 地址, 如果没有取默认地址
       set $cacheTime 300000; # 设置缓存时间, 如果没有取默认时间
       set $requestRandom 'UJ8neK2pVrxhkc23D2oD'; # 设置请求随机数, 如果没有取默认随机数
       content_by_lua_file /home/nginx-code/lib/index.lua;
     }
    ```

2. config.json
    ```json
    {
       "usePenetrate": true, 
       "timeout": 10000,
       "rootDir": "/home/www",
       "xmlDir": "config",
       "localTokenName": "token",
       "tokenName": "penetrate-token",
       "cacheTime": "60000",
       "requestRandom": "DMb7vr4RRRpxImkSBWAk",
       "redis": {
          "host": "127.0.0.1",
          "port": 6379,
          "auth": "%ZwpH&mkzxHrqKLh"
       }
    }
    ```
   
    * 属性
      - usePenetrate: 是否使用穿透框架, 默认为 `true`
      - timeout: 请求超时时间, 默认 10s
      - rootDir: 项目配置目录, 默认为 `/home/www`
      - xmlDir: 项目的 xml 配置目录名称, 默认在项目根目录的 `config` 下
      - localTokenName: 默认发送到客户端的 `token` 名称, 如果在 `config.xml` 中没有配置 `defaultLocalTokenName`, 则取这个
      - tokenName: 默认发送到服务端的 `token` 名称, 如果在 `config.xml` 中没有配置 `tokenName`, 则取这个
      - cacheTime: 默认缓存时间, 60 s
      - requestRandom: 默认请求随机数
      - redis: redis 配置, 包括 `host`、 `post`、 `auth`

3. 项目配置文件<br/>
   存放于 `项目根目录` 下的 `config` 下。
   - config.xml 配置如下:
  ```xml
    <!--
        environment: 环境名称, 当前激活的环境名为 module.xml 中 apis 节点上的 environment 属性
        properties: 多个域名配置, module.xml 中通过 address 查找它
        property:
                - timeout: 超时时间, 默认为 10000(10s)
                - host: 域名
                - protocol: 协议, https 或 http
                - localTokenName: 本地 token 名称, 默认为 config.json 中的 localTokenName
                - tokenName: 请求 token 名称, 默认为 config.json 中的 tokenName
    -->
    <configs>
        <config environment="prod">
            <properties name="chat">
                <property name="timeout" value="10000"/>
                <property name="host" value="example.com" deploy="_apigateway_" />
                <property name="protocol" value="https" deploy="_https_" />
                <property name="localTokenName" value="chat-token"/>
                <property name="tokenName" value="chat_api_token"/>
            </properties>
            
            <!-- 其他配置 -->
        </config>
    
        <config environment="test">
            <properties name="chat">
                <property name="timeout" value="10000"/>
                <property name="host" value="example.test.com" deploy="_apigateway_" />
                <property name="protocol" value="https" deploy="_https_" />
                <property name="localTokenName" value="chat-token"/>
                <property name="tokenName" value="chat_api_token"/>
            </properties>
            
             <!-- 其他配置 -->
        </config>
    
        <!-- 其他配置 -->
    </configs>
  ```

   - module.xml
  ```xml
    <!--
      environment: 环境名称, 对应 config.xml 中的 environment
      api:
          - uri: 请求地址
          - type: 0: 一般请求, 1 登录, 2: 登出, 默认为 0
          - address: 对应 config.xml 中的 properties 上的 name 属性
          - auth: 0: 鉴权, 1: 跳过鉴权, 默认为 0
          - destination:
            - header: header 的组成, $1 替换为 token
            - method: 真实请求方法
            - uri: 真实请求 uri, 通过获取 config.xml 中的 host 来拼接成完整的 url
    -->
    <apis environment="prod">
        <!-- 登录 -->
        <api>
            <uri>/v1/login</uri>
            <type>1</type>
            <address>remark</address>
            <destination>
                <method>POST</method>
                <uri>/open/remarkApi/login</uri>
            </destination>
        </api>
    
        <!-- 查询 -->
        <api>
            <uri>/v1/query</uri>
            <type>0</type>
            <address>remark</address>
            <destination>
                <!-- $1 需要替换为 token -->
                <header>gpt:employee-token:$1</header>
                <method>POST</method>
                <uri>/open/remarkApi/category/query</uri>
            </destination>
        </api>
    
        <!-- 登出 -->
        <api>
            <uri>/v1/logout</uri>
            <type>2</type>
            <address>remark</address>
            <destination>
                <method>POST</method>
                <uri>/open/remarkApi/logout</uri>
            </destination>
        </api>

        <!-- 其他配置 -->
    </apis>
  ```

## 使用
1. 登录<br/>
   登录成功后会把 `token` 等值存到 `redis`, `key` 为 `项目名称`, 再把 `localToken` 放在 `header` 中 和 `data` 中返回。

   ```text
   请求地址: https://example.com/chat/v1/login
   请求方法: POST
   请求参数: {
       "version": "1.0",
       "data": {
           "test": "123456"
       }
   }
   ```

2. 查询<br/>
   查询需要在 `header` 里带上 `localToken`。
   ```text
   请求地址: https://example.com/chat/v1/query?test=1234&version=1.0
   请求方法: GET
   ```

   ```text
   请求地址: https://example.com/chat/v1/query
   请求方法: POST
   请求参数: {
       "version": "1.0",
       "data": {
           "test": "123456"
       }
   }
   ```

3. 登出<br/>
   登出会删除 `redis` 中的值。
   ```text
   请求地址: https://example.com/chat/v1/logout
   请求方法: POST
   请求参数: {
       "version": "1.0",
       "data": {
           "test": "123456"
       }
   }
   ```