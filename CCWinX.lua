local _FORK = _FORK
if term.setGraphicsMode == nil then error("CCWinX requires CraftOS-PC v1.2 or later.") end
_ = os.loadAPI("CCLog.lua") or (shell and os.loadAPI(fs.getDir(shell.getRunningProgram()) .. "/CCLog.lua")) or print("CCLog not installed, logging will be disabled.")
local log = CCLog and (CCLog.CCLog and CCLog.CCLog("CCWinX") or CCLog("CCWinX")) or {log = function() end, debug = function() end, info = function() end, warn = function() end, error = function() end, critical = function() end, traceback = function() end, open = function() end, close = function() end}

local CCWinX = {}
local displays = {}

--- Opens a display for a program to use.
-- @param id The id of the monitor (either a string, or a number: 0 = native terminal, >0 = monitor id + 1 ("monitor_1" = 2))
-- @return An object describing the display or nil
function CCWinX.OpenDisplay(client, id)
    if displays[id] ~= nil then 
        for k,v in pairs(retval.clients) do if v == client then
            log:warn("Already opened display: " .. id)
            return displays[id]
        end end
        table.insert(displays[id].clients, client)
        return displays[id] 
    end
    local retval = {}
    retval.id = id
    retval.server = _PID
    retval.clients = {client}
    retval.windows = {}
    if type(id) == "string" and peripheral.getType(id) == "monitor" then
        local t = peripheral.wrap(id)
        t.clear()
        t.setCursorPos(1, 1)
        t.setCursorBlink(false)
        setmetatable(retval, {__index = function(key) return t[key] end})
    elseif type(id) == "number" and id == 0 then
        local native = term.native()
        native.clear()
        native.setCursorPos(1, 1)
        native.setCursorBlink(false)
        setmetatable(retval, {__index = function(key) return native[key] end})
    elseif type(id) == "number" and peripheral.isPresent("monitor_" .. (id + 1)) then
        local t = peripheral.wrap("monitor_" .. (id + 1))
        t.clear()
        t.setCursorPos(1, 1)
        t.setCursorBlink(false)
        setmetatable(retval, {__index = function(key) return t[key] end})
    else
        log:error("Cannot open display: " .. id)
        return nil
    end
    displays[id] = retval
    return retval
end

--- Closes a display object and the windows associated with it.
-- @param disp The display object
-- @return Whether the command succeeded
function CCWinX.CloseDisplay(client, disp)
    if type(disp) ~= "table" then
        log:error("Type error at CloseDisplay (#1): expected table, got " .. type(disp))
        return false
    end
    local opened = false
    for k,v in pairs(retval.clients) do if v == client then
        opened = true
        table.remove(retval.clients, k)
        break
    end end
    if not opened then
        log:error("Display not opened: " .. disp.id)
        return false
    end
    local delete = {}
    for k,v in pairs(retval.windows) do if v.owner == client then table.insert(delete, k) end end
    for k,v in pairs(delete) do
        -- close window properly
    end
    if #disp.clients == 0 then
        disp.clear()
        disp.setCursorPos(1, 1)
        disp.setCursorBlink(true)
        disp.setBackgroundColor(colors.black)
        disp.setTextColor(colors.white)
        displays[id] = nil
        disp = nil
    end
    return true
end

--- Creates a window.
-- @param display The display to create the window on
-- @param parent The parent window of the new window
-- @param x The X coordinate of the window
-- @param y The Y coordinate of the window
-- @param width The width of the window
-- @param height The height of the window
-- @param border_width The width of the window border
-- @param class The class of the window
-- @param attribute A table of attributes applied to the window.
-- @return A window object
function CCWinX.CreateWindow(client, display, parent, x, y, width, height, border_width, class, attribute)
    local retval = {}

end

--- Creates a simple window.
-- @param display The display to create the window on
-- @param parent The parent window of the new window
-- @param x The X coordinate of the window
-- @param y The Y coordinate of the window
-- @param width The width of the window
-- @param height The height of the window
-- @param border_width The width of the window border
-- @param border The color of the border
-- @param background The color of the background
-- @return A window object
function CCWinX.CreateSimpleWindow(client, display, parent, x, y, width, height, border_width, border, background)

end

-- If run under CCKernel2 through a shell or forked: start a CCWinX server to listen to apps
-- If loaded as an API under CCKernel2: provide functions to send messages to a CCWinX server
-- If run without CCKernel2 through a shell: do nothing
-- If loaded as an API without CCKernel2: provide functions to run a server through messages

local function ServeWindows(...)

end

if shell or _FORK then
    if kernel then
        log:open()
        log:info("CCWinX Server v0.0.1")
        log:info("Running " .. os.version() .. " on host " .. _HOST)
        while true do
            local args = {os.pullEvent()}
            local ev = table.remove(args, 1)
            if ev == "key" or ev == "char" or ev == "key_up" then
                local pids = {}
                for k,v in pairs(displays) do for l,w in pairs(v.clients) do if not pids[w] then
                    kernel.send(w, ev, table.unpack(args))
                    pids[w] = true
                end end end
            elseif ev == "mouse_click" or ev == "mouse_up" or ev == "mouse_drag" or ev == "mouse_scroll" then
                -- Handle mouse events
            end
            local pid = table.remove(args, 1)
            if ev == "CCWinX.GetServerPID" and type(pid) == "number" then
                kernel.send(pid, "CCWinX.ServerPID", _PID)
            elseif type(CCWinX[ev]) == "function" then
                kernel.send(pid, "CCWinX."..ev, CCWinX[ev](pid, table.unpack(args)))
            end
            ServeWindows(ev, pid, table.unpack(args))
        end
    else
        print("CCWinX requires CCKernel2 to run in server mode. Without CCKernel2, programs can only load CCWinX as an API.")
    end
else
    if kernel then
        kernel.broadcast("CCWinX.GetServerPID", _PID)
        local i = 0
        local pid
        while i < 3 do
            local ev, p = os.pullEvent()
            if ev == "CCWinX.ServerPID" then
                pid = p
                break
            end
            i=i+1
        end
        if pid == nil then error("Could not find any running CCWinX server. Please start a server before loading CCWinX.") end
        for k,v in pairs(CCWinX) do
            _ENV[k] = function(...) 
                kernel.send(pid, k, ...)
                return os.pullEvent("CCWinX." .. k)
            end
        end
    else
        for k,v in pairs(CCWinX) do _ENV[k] = function(...) return CCWinX[k](0, ...) end end
    end
end