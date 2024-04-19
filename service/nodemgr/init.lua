local skynet = require "skynet"
local s = require "service"

function hex(str)
    if str==nil or tonumber(str)==nil then
        return "nil"
    end
    return string.format("%x",tonumber(str))
end

s.resp.newservice = function (source,name,...)
    skynet.error("nodemgr new service:"..name.." and source is "..hex(source))
    local srv = skynet.newservice(name,...)
    return srv
end

s.start(...)