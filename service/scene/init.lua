local skynet = require "skynet"
local cluster = require "skynet.cluster"
local foods = {}
local balls = {}
local food_maxid = 0
local food_count = 0
local messages = {} -- 消息列表
local resp = {} -- 响应函数表
local pending_movemsg_outputs = {} -- 等待转发move消息，move消息会统一转发，只转发最新回复消息，其他消息，立即转发

local function hex(str)
    if str == nil or tonumber(str) == nil then
        return "nil"
    end
    return string.format("%x", tonumber(str))
end

local function balllist_msg()
    local msg = {"balllist"}
    for i, v in pairs(balls) do
        table.insert(msg, v.playerid)
        table.insert(msg, v.x)
        table.insert(msg, v.y)
        table.insert(msg, v.size)
        table.insert(msg, v.score)
    end
    return msg
end

local function foodlist_msg()
    local msg = {"foodlist"}
    for i, v in pairs(foods) do
        table.insert(msg, v.id)
        table.insert(msg, v.x)
        table.insert(msg, v.y)
        table.insert(msg, v.size)
        table.insert(msg, v.score)
    end
    return msg
end

-- 正态分布函数
local function generate_normal_distribution(mean, stddev)
    local u1 = math.random()
    local u2 = math.random()

    local z0 = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
    local z1 = math.sqrt(-2 * math.log(u1)) * math.sin(2 * math.pi * u2)

    return z0 * stddev + mean, z1 * stddev + mean
end

-- 食物
local function food()
    local m = {
        id = nil,
        x = math.random(-50, 50),
        y = math.random(-50, 50),
        -- 每个球的分数随机初始化为1~10，但所有食物分数符合正态分布
        score = math.max(math.min(math.floor(generate_normal_distribution(2, 2)), 10), 1)
    }
    m.size = m.score * 0.1
    return m
end

local function ball()
    local m = {
        playerid = nil,
        node = nil,
        agent = nil,
        x = math.random(-50, 50),
        y = math.random(-50, 50),
        size = 0.1,
        score = 1,
        speed = 1
    }
    return m
end

local function send(node, srv, ...)
    local mynode = skynet.getenv("node")
    if node == mynode then
        return skynet.send(srv, "lua", ...)
    else
        return cluster.send(node, srv, ...)
    end
end

local function broadcast(msg)
    for i, v in pairs(balls) do
        send(v.node, v.agent, "send", msg)
    end
end

resp.enter = function(playerid, node, agent)
    local enter_msg = nil
    if balls[playerid] then
        enter_msg = {"enter", 1, "alerdayinscene!"}
        send(node, agent, "send", enter_msg)
        return false
    end
    local b = ball()
    b.playerid = playerid
    b.node = node
    b.agent = agent
    -- 通知所有场景服务器中的玩家，有新玩家加入
    local addball_msg = {"addball", playerid, b.x, b.y, b.size, b.score}
    broadcast(addball_msg)
    balls[playerid] = b

    -- 回应请求加入的玩家
    enter_msg = {"enter", 0, "success"}
    send(b.node, b.agent, "send", enter_msg)
    -- 单独给新加入玩家发战场信息
    send(b.node, b.agent, "send", balllist_msg())
    send(b.node, b.agent, "send", foodlist_msg())
    return true
end

resp.leave = function(playerid)
    if not balls[playerid] then
        return false
    end
    balls[playerid] = nil

    local leavemsg = {"leave", playerid}
    broadcast(leavemsg)
end

local function food_update()
    if food_count > 50 then
        return
    end

    -- 保证每帧只有0.02的几率添加
    if math.random(1, 100) < 98 then
        return
    end

    food_maxid = food_maxid + 1
    food_count = food_count + 1
    local f = food()
    f.id = food_maxid
    foods[f.id] = f

    local msg = {"addfood", f.id, f.x, f.y, f.size, f.score}
    broadcast(msg)
end

resp.kill = function(player_id, session_id, secondball_id)
    local b1 = balls[player_id]
    secondball_id = tonumber(secondball_id)
    local b2 = balls[secondball_id]
    if not b1 or not b2 then
        return
    end

    if (b1.x - b2.x) ^ 2 + (b1.y - b2.y) ^ 2 <= ((b1.size + b2.size) ^ 2) / 4 then
        local predator_ball = nil -- 捕食者球
        local prey_ball = nil -- 被捕食者球

        if b1.score >= b2.score then -- b1是捕食者
            predator_ball = b1
            prey_ball = b2
        else -- b2是捕食者
            predator_ball = b2
            prey_ball = b1
        end
        predator_ball.score = predator_ball.score + prey_ball.score
        predator_ball.size = predator_ball.score * 0.1
        balls[prey_ball.playerid] = nil
        local msg = {"kill", session_id, 0, predator_ball.playerid, predator_ball.x, predator_ball.y,
                     predator_ball.size, predator_ball.score, prey_ball.playerid}
        broadcast(msg)
    else
        local msg = {"kill", session_id, 1, b1.playerid, b1.x, b1.y, b1.size, b1.score, b2.playerid, b2.x, b2.y,
                     b2.size, b2.score}
        send(b1.node, b1.agent, "send", msg)
    end
end

resp.eat = function(player_id, session_id, food_id)
    local b = balls[player_id]
    food_id = tonumber(food_id)
    local f = foods[food_id]
    if not b or not f then
        return
    end
    if (b.x - f.x) ^ 2 + (b.y - f.y) ^ 2 <= ((b.size + f.size) ^ 2) / 4 then
        b.score = b.score + f.score
        b.size = b.score * 0.1
        foods[food_id] = nil
        food_count = food_count - 1

        local msg = {"eat", session_id, 0, player_id, b.x, b.y, b.size, b.score, food_id}
        broadcast(msg)
    else
        local msg = {"eat", session_id, 1, player_id, b.x, b.y, b.size, b.score, food_id}
        send(b.node, b.agent, "send", msg)
    end
end

resp.move = function(player_id, session_id, input_x, input_y, dealt_time)
    local b = balls[player_id]
    if not b or tonumber(dealt_time) > 1 / 40 then
        return false
    end
    -- 应用输入
    b.x = b.x + b.speed * input_x * dealt_time;
    b.y = b.y + b.speed * input_y * dealt_time;
    -- 准备要回复的消息
    local msg = {"move", session_id, player_id, b.x, b.y, b.size, b.score}
    pending_movemsg_outputs[player_id] = msg -- 之后的sessionId大于现在的sessionId，因为TCP保证有序性
end

local function traceback(err)
    skynet.error(tostring(err))
    skynet.error(debug.traceback())
end

-- 每帧更新函数
local function update(frame)
    -- 1.处理客户端输入
    local len = #messages
    for i = 1, len, 1 do
        -- 从消息队列中取出消息
        local msg = messages[1]
        table.remove(messages, 1) -- 删除消息

        -- 调用响应消息处理函数
        local cmd = msg[1]
        local fun = resp[cmd]
        if cmd~="move" then
            skynet.error("update:" .. table.concat(msg,","))
        end

        if fun then
            local isok, res = xpcall(fun, traceback, table.unpack(msg, 2))
            if not isok then
                skynet.error(res);
            end
        else
            skynet.error("No fun " .. cmd);
        end
    end
    -- 2.发送move消息
    for id, msg in pairs(pending_movemsg_outputs) do
        pending_movemsg_outputs[id] = nil
        broadcast(msg)
    end
    -- 3.添加food
    food_update()
end

local function init()
    skynet.fork(function()
        -- 保持帧率执行
        local stime = skynet.now()
        local frame = 0
        while true do
            frame = frame + 1
            local isok, err = pcall(update, frame)
            if not isok then
                skynet.error(err)
            end
            -- 保持2*10ms的间隔 50fps
            local etime = skynet.now()
            local waittime = frame * 2 - (etime - stime) -- 50fps
            if waittime <= 0 then
                waittime = 0
            end
            skynet.sleep(waittime)
        end
    end)
end

local function dispatch(session, address, ...)
    local msg = {...}
    table.insert(messages, msg)
    skynet.retpack("true")
end

skynet.start(function()
    skynet.dispatch("lua", dispatch)
    init()
end)
