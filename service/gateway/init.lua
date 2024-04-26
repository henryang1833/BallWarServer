local skynet = require "skynet"
local s = require "service"
local socket = require "skynet.socket"
local runconfig = require "runconfig"
conns = {}
players = {}

function hex(str)
    if str == nil or tonumber(str) == nil then
        return "nil"
    end
    return string.format("%x", tonumber(str))
end

-- 连接类
function conn()
    local m = {
        fd = nil,
        playerid = nil
    }
    return m
end

-- 玩家类
function gateplayer()
    local m = {
        playerid = nil,
        agent = nil,
        conn = nil
    }
    return m
end

local str_unpack = function(msgstr)
    local msg = {}
    while true do
        local arg, rest = string.match(msgstr, "(.-),(.*)")
        if arg then
            msgstr = rest
            table.insert(msg, arg)
        else
            table.insert(msg, msgstr)
            break
        end
    end
    return msg[1], msg
end

local str_pack = function(msg)
    return table.concat(msg, ",") .. "\r\n"
end

-- 网关服务器处理消息逻辑
local process_msg = function(fd, msgstr)
    local cmd, msg = str_unpack(msgstr)
    -- skynet.error("recv " .. fd .. " [" .. cmd .. "] {" .. table.concat(msg, ",") .. "}")

    local conn = conns[fd]
    local playerid = conn.playerid
    -- 尚未完成登录流程
    if not playerid then
        local node = skynet.getenv("node")
        local nodecfg = runconfig[node]
        local loginid = math.random(1, #nodecfg.login)
        local login = "login" .. loginid
        skynet.send(login, "lua", "client", fd, cmd, msg)
        -- 完成登录流程
    else
        local gplayer = players[playerid]
        local agent = gplayer.agent
        skynet.send(agent, "lua", "client", cmd, msg)
    end
end

-- 从消息缓冲区中取出协议消息
local process_buff = function(fd, readbuff)
    while true do
        local msgstr, rest = string.match(readbuff, "(.-)\r\n(.*)")
        if msgstr then
            readbuff = rest
            process_msg(fd, msgstr)
        else
            return readbuff
        end
    end
end

local disconnect = function(fd)
    local c = conns[fd]
    if not c then
        return
    end

    local playerid = c.playerid
    -- 还没完成登录
    if not playerid then
        return
        -- 已在游戏中
    else
        players[playerid] = nil
        local reason = "断线"
        skynet.call("agentmgr", "lua", "reqkick", playerid, reason)
    end

    --------------------------------
    socket.close(fd)
end

s.resp.kick = function(source, playerid)
    local gplayer = players[playerid]
    if not gplayer then
        return
    end

    local c = gplayer.conn
    players[playerid] = nil

    if not c then
        return
    end
    ---------------------------
    disconnect(c.fd)
    conns[c.fd] = nil
    --------------------------
end

local recv_loop = function(fd)
    socket.start(fd)
    skynet.error("socket connected " .. hex(fd))
    local readbuff = ""
    while true do
        local recvstr = socket.read(fd)
        if recvstr then
            readbuff = readbuff .. recvstr
            readbuff = process_buff(fd, readbuff)
        else
            skynet.error("socket close " .. hex(fd))
            disconnect(fd)
            socket.close(fd)
            return
        end
    end
end

local connect = function(fd, addr)
    print("connect from " .. addr .. " " .. fd)
    local c = conn()
    conns[fd] = c
    c.fd = fd
    skynet.fork(recv_loop, fd)
end

function s.init()
    local node = skynet.getenv("node")
    local nodecfg = runconfig[node]
    local port = nodecfg.gateway[s.id].port

    local listenfd = socket.listen("0.0.0.0", port)
    skynet.error("Listen socket :" .. "0.0.0.0:" .. port)
    socket.start(listenfd, connect)
end

s.resp.send_by_fd = function(source, fd, msg)
    if not conns[fd] then
        return
    end
    local buff = str_pack(msg)
    socket.write(fd, buff)
end

s.resp.send = function(source, playerid, msg)
    local gplayer = players[playerid]
    if gplayer == nil then
        return
    end
    local c = gplayer.conn
    if c == nil then
        return
    end

    s.resp.send_by_fd(nil, c.fd, msg)
end

s.resp.sure_agent = function(source, fd, playerid, agent)
    local conn = conns[fd]
    if not conn then -- 登录过程中已经下线
        skynet.call("agentmgr", "lua", "reqkick", playerid, "未完成登录即下线")
        return false
    end

    conn.playerid = playerid

    local gplayer = gateplayer()
    gplayer.playerid = playerid
    gplayer.agent = agent
    gplayer.conn = conn
    players[playerid] = gplayer

    return true
end

s.start(...)
