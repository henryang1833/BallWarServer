local skynet = require "skynet"
local s = require "service"

s.gate = nil
s.client = {}

require "scene"

local function hex(str)
    if str==nil or tonumber(str)==nil then
        return "nil"
    end
    return string.format("%x",tonumber(str))
end


s.resp.client = function (source,cmd,msg)
    -- skynet.error("s.resp.client,source:"..hex(source)..",cmd:"..cmd..",msg:"..table.concat(msg,","))
    s.gate = source
    if s.client[cmd] then --client 是客户发来的消息
        local ret_msg = s.client[cmd](msg,source)
        if ret_msg then
            skynet.send(source,"lua","send",s.id,ret_msg)
        end
    else
        skynet.error("s.resp.client fail",cmd)
    end
end

s.init = function ()
    --playerid = s.id
    --在此处加载角色数据
    skynet.sleep(200)
    s.data = {
        coin = 100,
        hp = 200
    }
end

s.resp.kick = function (source)
    s.leave_scene()
    --在此处加载角色数据
    skynet.sleep(200)
end

s.resp.exit = function (source)
    skynet.exit()
end

s.client.work = function (msg)
    s.data.coin = s.data.coin + 1
    return {"work",s.data.coin}
end

s.resp.send = function (source,msg)
    skynet.send(s.gate,"lua","send",s.id, msg)
end

s.start(...)