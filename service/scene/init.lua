skynet  = require "skynet"
s = require "service"
local foods = {}
local balls = {}
local food_maxid = 0
local food_count = 0

function hex(str)
    if str==nil or tonumber(str)==nil then
        return "nil"
    end
    return string.format("%x",tonumber(str))
end

local function balllist_msg()
    local msg = {"balllist"}
    for i,v in pairs(balls) do
        table.insert(msg,v.playerid)
        table.insert(msg,v.x)
        table.insert(msg,v.y)
        table.insert(msg,v.size)
    end
    return msg
end

local function foodlist_msg()
    local msg = {"foodlist"}
    for i,v in pairs(foods) do
        table.insert(msg,v.id)
        table.insert(msg,v.x)
        table.insert(msg,v.y)
        table.insert(msg,v.size)
    end
    skynet.error("foodlist:"..table.concat(msg,","))
    return msg
end

-- 正态分布函数
function generate_normal_distribution(mean, stddev)
    local u1 = math.random()
    local u2 = math.random()
    
    local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    local z1 = math.sqrt(-2 * math.log(u1)) * math.sin(2 * math.pi * u2)
    
    return z0 * stddev + mean, z1 * stddev + mean
end

--食物
function  food()
    local m = {
        id = nil,
        x = math.random(-50,50),
        y = math.random(-50,50),
        size = math.max(math.min(math.floor(math.abs(generate_normal_distribution(2,2))),10),1) * 0.2
    }
    return m
end


function  ball()
    local m = {
        playerid = nil,
        node = nil,
        agent = nil,
        x = math.random(-50,50),
        y = math.random(-50,50),
        size = 0.5,
        speedx = 0,
        speedy = 0
    }
    return m
end

function broadcast(msg)
    for i,v in pairs(balls) do
        s.send(v.node,v.agent,"send",msg)
    end
end

s.resp.enter = function (source,playerid,node,agent)
    skynet.error("s.resp.enter,source:"..hex(source)..",playerid:"..playerid..",node:"..node..",agent:"..hex(agent))
    if balls[playerid] then
        return false
    end
    local b = ball()
    b.playerid = playerid
    b.node = node
    b.agent = agent
    --广播
    local entermsg = {"enter",playerid,b.x,b.y,b.size}
    broadcast(entermsg)
    --记录
    balls[playerid] = b
    --回应
    local ret_msg = {"enter",0,"进入成功"}
    s.send(b.node,b.agent,"send",ret_msg)
    --发战场信息
    s.send(b.node,b.agent,"send",balllist_msg())
    s.send(b.node,b.agent,"send",foodlist_msg())
    return true
end

s.resp.leave = function (source,playerid)
    if not balls[playerid] then
        return false
    end
    balls[playerid] = nil

    local leavemsg = {"leave",playerid}
    broadcast(leavemsg)
end

s.resp.shift = function (source,playerid,x,y)
    skynet.error("s.resp.shift,source:"..hex(source)..",playerid:"..playerid..",x:"..x..",y:"..y)
    local b = balls[playerid]
    if not b then
        return false
    end
    b.speedx = x
    b.speedy = y
end

function move_update()
    for i, v in pairs(balls) do
        v.x = v.x + v.speedx * 0.04
        v.y = v.y + v.speedy * 0.04
        if v.speedx ~= 0 or v.speedy ~= 0 then
            local msg = {"move",v.playerid,v.x,v.y}
            broadcast(msg)
        end
    end
end

function food_update()
    if food_count > 50 then
        return
    end

    if math.random(1,100) < 98 then
        return
    end

    food_maxid = food_maxid + 1
    food_count = food_count + 1
    local f = food()
    f.id  = food_maxid
    foods[f.id] = f

    local msg = {"addfood",f.id,f.x,f.y,f.size}
    broadcast(msg)
end

function eat_update()
    for pid,b in pairs(balls) do
        for fid, f in pairs(foods) do
            if (b.x - f.x)^2 + (b.y - f.y)^2 < ((b.size + f.size)^2)/4 then
                b.size = math.sqrt(b.size^2 + f.size^2)
                food_count = food_count - 1
                local msg = {"eat",b.playerid,fid,b.size}
                broadcast(msg)
                foods[fid] = nil --warm
            end
        end
    end
end

function  update(frame)
    food_update()
    move_update()
    eat_update()
    --碰撞略
    --分裂略
end

s.init = function ()
    skynet.fork(function ()
        --保持帧率执行
        local stime = skynet.now()
        local frame = 0
        while true do
            frame = frame + 1
            local isok,err = pcall(update,frame)
            if not isok then
                skynet.error(err)
            end
            local etime = skynet.now()
            local waittime = frame * 2 - (etime - stime) -- 50fps
            if waittime <=0 then
                waittime = 0
            end
            skynet.sleep(waittime)
        end
    end)
end

s.start(...)