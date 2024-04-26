local skynet = require "skynet"
local s = require "service"
local runconfig = require "runconfig"
local mynode = skynet.getenv("node")

s.snode = nil -- scene_node
s.sname = nil -- scene_id

local function hex(str)
    if str == nil or tonumber(str) == nil then
        return "nil"
    end
    return string.format("%x", tonumber(str))
end

local function random_scene()
    -- 选择node
    local nodes = {}
    for i, v in pairs(runconfig.scene) do
        table.insert(nodes, i)
        if runconfig.scene[mynode] then
            table.insert(nodes, mynode)
        end
    end
    local idx = math.random(1, #nodes)
    local scenenode = nodes[idx]
    -- 具体场景
    local scenelist = runconfig.scene[scenenode]
    local idx = math.random(1, #scenelist)
    local sceneid = scenelist[idx]
    return scenenode, sceneid
end

s.client.enter = function(msg)
    if s.sname then
        return {"enter", 1, "agent:alreadyinscene"}
    end
    local snode, sid = random_scene()
    local sname = "scene" .. sid
    local isok = s.call(snode, sname, "enter", s.id, mynode, skynet.self())
    if not isok then
        return {"enter", 1, "agent:enterfail"}
    end
    s.snode = snode
    s.sname = sname
    return nil
end

s.leave_scene = function()
    -- 不在场景
    if not s.sname then
        return
    end
    s.call(s.snode, s.sname, "leave", s.id)
    s.snode = nil
    s.sname = nil
end

s.resp.kick = function(source)
    s.leave_scene()
    -- 在此处保存角色数据
    skynet.sleep(200)
end

s.client.move = function(msg)
    if not s.sname then
        skynet.error("not s.sname:" .. s.sname)
        return
    end
    local sessionId = msg[2] or 0
    local x = msg[3] or 0.0
    local y = msg[4] or 0.0
    local dealtTime = msg[5] or 0
    s.call(s.snode, s.sname, "move", s.id, sessionId, x, y, dealtTime)
end

s.client.eat = function(msg)
    skynet.error("s.client.eat msg:" .. table.concat(msg, ","))
    if not s.sname then -------------s.sname == nil?
        skynet.error("not s.sname:" .. s.sname)
        return
    end
    local sessionId = msg[2] or 0
    local fid = msg[3] or 0
    s.call(s.snode, s.sname, "eat", s.id, sessionId, fid)
end

s.client.kill = function(msg)
    skynet.error("s.client.eat msg:" .. table.concat(msg, ","))
    if not s.sname then -------------s.sname == nil?
        skynet.error("not s.sname:" .. s.sname)
        return
    end
    local sessionId = msg[2] or 0
    local fid = msg[3] or 0
    s.call(s.snode, s.sname, "kill", s.id, sessionId, fid)
end

