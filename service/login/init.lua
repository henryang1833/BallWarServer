local skynet = require "skynet"
local s = require "service"

function hex(str)
    if str==nil or tonumber(str)==nil then
        return "nil"
    end
    return string.format("%x",tonumber(str))
end

s.client = {}
s.resp.client = function(source,fd,cmd,msg)
    if s.client[cmd] then
        local ret_msg = s.client[cmd](fd,msg,source)
        skynet.send(source,"lua","send_by_fd",fd,ret_msg)
    else
        skynet.error("s.resp.client fail",cmd)
    end
end

s.client.login = function (fd,msg,source)
    skynet.error("try login: fd is "..hex(fd)..",msg is "..table.concat(msg,":")..",source is "..hex(source))
    local playerid = tonumber(msg[2])
    local pw = tonumber(msg[3])
    local gate = source
    node = skynet.getenv("node")
    --校验用户名和密码
    if pw~=123 then
        skynet.error("密码错误")
        return {"login",1,"密码错误"}
    end

    skynet.error("发给agentmgr")
    --发给agentmgr
    local isok,agent = skynet.call("agentmgr","lua","reqlogin",playerid,node,gate)
    if not isok then
        skynet.error("请求mgr失败")
        return {"login",1,"请求mgr失败"}
    end

    skynet.error("回应gate")
    --回应gate
    local isok = skynet.call(gate,"lua","sure_agent",fd,playerid,agent)
    if not isok then
        skynet.error("gate注册失败")
        return {"login",1,"gate注册失败"}
    end
    skynet.error("login succ"..playerid)
    -- return {"login",0,"登录成功"}
    return {"login",0,"success"}
end

s.start(...)