local _FORK = _FORK
if term.setGraphicsMode == nil then error("CCWinX requires CraftOS-PC v1.2 or later.") end
_ = os.loadAPI("CCLog.lua") or (shell and os.loadAPI(fs.getDir(shell.getRunningProgram()) .. "/CCLog.lua")) or print("CCLog not installed, logging will be disabled.")
local log = CCLog and (CCLog.CCLog and CCLog.CCLog("CCWinX") or CCLog("CCWinX")) or {log = function() end, debug = function() end, info = function() end, warn = function() end, error = function() end, critical = function() end, traceback = function() end, open = function() end, close = function() end}

local CCWinX = {}
local displays = {}

local function qs(tab)
    if (type(tab) ~= "table" and type(tab) ~= "function") or kernel then return tab end
    if type(tab) == "function" then return nil end
    local retval = {}
    for k,v in pairs(tab) do retval[makeQueueSafe(k)] = makeQueueSafe(v) end
    return retval
end
local function sendEvent(...) if kernel then kernel.broadcast(...) else os.queueEvent(...) end end

Error = {
    BadColor = 0,
    BadMatch = 1,
    BadValue = 2,
    BadWindow = 3
}

StackMode = {
    Above = 0,
    Below = 1,
    TopIf = 2,
    BottomIf = 3,
    Opposite = 4
}

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
        setmetatable(retval, {__index = function(key) return t[key] end})
    elseif type(id) == "number" and id == 0 then
        local native = term.native()
        setmetatable(retval, {__index = function(key) return native[key] end})
    elseif type(id) == "number" and peripheral.isPresent("monitor_" .. (id + 1)) then
        local t = peripheral.wrap("monitor_" .. (id + 1))
        setmetatable(retval, {__index = function(key) return t[key] end})
    else
        log:error("Cannot open display: " .. id)
        return nil
    end
    retval.setGraphicsMode(true)
    local w, h = retval.getSize()
    
    local root = {}
    root.owner = client
    root.display = retval
    root.frame = {}
    root.frame.x = 0
    root.frame.y = 0
    root.frame.width = w * 6
    root.frame.height = h * 9
    root.class = 1 -- may use later
    root.attributes = {}
    root.border = {}
    root.border.width = 0
    root.border.color = nil
    root.buffer = {}
    root.children = {}
    function root.clear()
        for y = 1, frame.height do
            root.buffer[y] = {}
            for x = 1, frame.width do
                root.buffer[y][x] = root.default_color
            end
        end
    end
    function root.setPixel(x, y, c) root.buffer[y][x] = c end
    function root.getPixel(x, y) return root.buffer[y][x] end
    function root.draw()
        for y,r in pairs(root.buffer) do for x,c in pairs(r) do 
            retval.setPixel(root.frame.x + x, root.frame.y + y, c or retval.getPixel(root.frame.x + x, root.frame.y + y)) 
        end end
    end
    root.clear()
    root.draw()
    retval.root = root

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
    for k,v in pairs(disp.clients) do if v == client then
        opened = true
        table.remove(disp.clients, k)
        break
    end end
    if not opened then
        log:error("Display not opened: " .. disp.id)
        return false
    end
    local delete = {}
    for k,v in pairs(disp.windows) do if v.owner == client then table.insert(delete, k) end end
    for k,v in pairs(delete) do
        -- close window properly
    end
    if #disp.clients == 0 then
        term.setGraphicsMode(false)
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
-- @param attributes A table of attributes applied to the window.
-- @return A window object
function CCWinX.CreateWindow(client, display, parent, x, y, width, height, border_width, class, attributes)
    if x + width > parent.width or y + height > parent.height then
        return Error.BadValue
    end
    if type(parent) ~= nil 
        or parent.default_color == nil 
        or parent.border == nil 
        or parent.border.color == nil 
        or parent.setPixel == nil 
        or parent.children == nil then
        return Error.BadWindow
    end
    local retval = {}
    retval.owner = client
    retval.display = display
    retval.parent = parent
    retval.frame = {}
    retval.frame.x = x
    retval.frame.y = y
    retval.frame.width = width
    retval.frame.height = height
    retval.class = class or parent.class -- may use later
    retval.attributes = attributes or {}
    retval.default_color = parent.default_color
    retval.border = {}
    retval.border.width = border_width
    retval.border.color = parent.border.color
    retval.buffer = {}
    retval.children = {}
    function retval.clear()
        for y = 1, frame.height do
            retval.buffer[y] = {}
            for x = 1, frame.width do
                retval.buffer[y][x] = retval.default_color
            end
        end
    end
    function retval.setPixel(x, y, c) retval.buffer[y][x] = c end
    function retval.getPixel(x, y) return retval.buffer[y][x] end
    function retval.draw()
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.setPixel(retval.frame.x + x, retval.frame.y + y, c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", false, display, parent, retval, x, y, width, height, border_width, retval.attributes.override_redirect)
    return retval
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
    if x + width > parent.width or y + height > parent.height then
        return Error.BadValue
    end
    if type(parent) ~= nil 
        or parent.default_color == nil 
        or parent.border == nil 
        or parent.border.color == nil 
        or parent.setPixel == nil 
        or parent.children == nil then
        return Error.BadWindow
    end
    local retval = {}
    retval.owner = client
    retval.display = display
    retval.parent = parent
    retval.frame = {}
    retval.frame.x = x
    retval.frame.y = y
    retval.frame.width = width
    retval.frame.height = height
    retval.class = 1 -- may use later
    retval.attributes = {}
    retval.default_color = background
    retval.border = {}
    retval.border.width = border_width
    retval.border.color = border
    retval.buffer = {}
    retval.children = {}
    function retval.clear()
        for y = 1, frame.height do
            retval.buffer[y] = {}
            for x = 1, frame.width do
                retval.buffer[y][x] = retval.default_color
            end
        end
    end
    function retval.setPixel(x, y, c) retval.buffer[y][x] = c end
    function retval.getPixel(x, y) return retval.buffer[y][x] end
    function retval.draw()
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.setPixel(retval.frame.x + x, retval.frame.y + y, c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", false, qs(display), qs(parent), qs(retval), x, y, width, height, border_width, retval.attributes.override_redirect)
    return retval
end

--- Changes the attributes of a window.
-- @param display The display for the window
-- @param w The window to modify
-- @param attributes A table of attributes to modify
function CCWinX.ChangeWindowAttributes(client, display, w, attributes)
    if type(w) ~= "table" or w.attributes == nil then return Error.BadWindow end
    for k,v in pairs(attributes) do w.attributes[k] = v end
end

--- Moves the top child of a window to the bottom.
-- @param display The display for the window
-- @param w The window to change the children of
function CCWinX.CirculateSubwindowsDown(client, display, w)
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    table.insert(w.children, table.remove(w.children, 1))
end

--- Moves the bottom child of a window to the top.
-- @param display The display for the window
-- @param w The window to change the children of
function CCWinX.CirculateSubwindowsUp(client, display, w)
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    table.insert(w.children, 1, table.remove(w.children, table.maxn(w.children)))
end

--- Moves the bottom or top child of a window to the top or bottom, respectively.
-- @param display The display for the window
-- @param w The window to change the children of
-- @param up Whether to go up (true) or down (false)
function CCWinX.CirculateSubwindows(client, display, w, up)
    if up then return CCWinX.CirculateSubwindowsUp(client, display, w) 
    else return CCWinX.CirculateSubwindowsDown(client, display, w) end
end

--- Clears a rectangular area in a window.
-- @param display The display for the window
-- @param w The window to modify
-- @param x The X coordinate of the area
-- @param y The Y coordinate of the area
-- @param width The width of the area
-- @param height The height of the area
-- @param exposures Whether to queue an Expose event
function CCWinX.ClearArea(client, display, w, x, y, width, height, exposures)
    if type(w) ~= "table" or w.frame == nil or w.buffer == nil then return Error.BadWindow end
    if x + width > w.frame.width or y + height > w.frame.height then return Error.BadValue end
    for py = y, y + height do for px = x, x + width do
        w.setPixel(px, py, w.default_color)
    end end
    if exposures then sendEvent("Expose", false, qs(display), qs(w), x, y, width, height, 0) end
end

--- Clears an entire window.
-- @param display The display for the window
-- @param w The window to clear
function CCWinX.ClearWindow(client, display, w)
    if type(w) ~= "table" or w.clear == nil or w.buffer == nil then return Error.BadWindow end
    w.clear()
end

--- Changes a window's size, position, border, and stacking order.
-- @param display The display for the window
-- @param w The window to modify
-- @param values The changes to make as table {x, y, width, height, border_width, sibling, stack_mode}
function CCWinX.ConfigureWindow(client, display, w, values)
    if type(w) ~= "table" or w.frame == nil or w.border == nil or w.parent == nil then return Error.BadWindow end
    if values.x ~= nil or values.y ~= nil or values.border_width ~= nil then
        w.frame.x = values.x or w.frame.x
        w.frame.y = values.y or w.frame.y
        w.border.width = values.border_width or w.border.width
    end
    if values.height ~= nil then
        if values.height > w.frame.height then
            for y = w.frame.height + 1, values.height do
                w.buffer[y] = {}
                for x = 1, w.frame.width do
                    w.buffer[y][x] = w.default_color
                end
            end
        elseif values.height < w.frame.height then
            for y = values.height + 1, w.frame.height do
                w.buffer[y] = {}
                for x = 1, w.frame.width do
                    w.buffer[y][x] = w.default_color
                end
            end
        end
        w.frame.height = values.height
    end
    if values.width ~= nil then
        if values.width > w.frame.width then
            for y = 1, w.frame.height do
                for x = w.frame.width + 1, values.width do
                    w.buffer[y][x] = w.default_color
                end
            end
        elseif values.width < w.frame.width then
            for y = 1, w.frame.height do
                for x = values.width + 1, w.frame.width do
                    w.buffer[y][x] = w.default_color
                end
            end
        end
        w.frame.width = values.width
    end
    if values.sibling ~= nil then
        if values.stack_mode == nil then return Error.BadMatch end
        local window_id
        for k,v in pairs(w.parent.children) do if v == w then
            window_id = k
            break
        end end
        if window_id == nil then return Error.BadWindow end
        local sibling_id
        for k,v in pairs(w.parent.children) do if v == w then
            sibling_id = k
            break
        end end
        if sibling_id == nil then return Error.BadMatch end
        if values.stack_mode == StackMode.Above then
            table.insert(w.parent.children, sibling_id, table.remove(w.parent.children, window_id))
        elseif values.stack_mode == StackMode.Below then
            table.insert(w.parent.children, sibling_id + 1, table.remove(w.parent.children, window_id))
        elseif values.stack_mode == StackMode.TopIf then
            if (values.sibling.frame.x <= w.frame.x + w.frame.width
                or values.sibling.frame.y <= w.frame.y + w.frame.height
                or values.sibling.frame.x + values.sibling.frame.width < w.frame.x
                or values.sibling.frame.y + values.sibling.frame.height < w.frame.y)
                and sibling_id < window_id then
                table.insert(w.parent.children, 1, table.remove(w.parent.children, window_id))
            end
        elseif values.stack_mode == StackMode.BottomIf then
            if (values.sibling.frame.x <= w.frame.x + w.frame.width
                or values.sibling.frame.y <= w.frame.y + w.frame.height
                or values.sibling.frame.x + values.sibling.frame.width < w.frame.x
                or values.sibling.frame.y + values.sibling.frame.height < w.frame.y)
                and sibling_id > window_id then
                table.insert(w.parent.children, table.remove(w.parent.children, window_id))
            end
        elseif values.stack_mode == StackMode.Opposite then
            if (values.sibling.frame.x <= w.frame.x + w.frame.width
                or values.sibling.frame.y <= w.frame.y + w.frame.height
                or values.sibling.frame.x + values.sibling.frame.width < w.frame.x
                or values.sibling.frame.y + values.sibling.frame.height < w.frame.y)
                and sibling_id < window_id then
                table.insert(w.parent.children, 1, table.remove(w.parent.children, window_id))
            elseif (values.sibling.frame.x <= w.frame.x + w.frame.width
                or values.sibling.frame.y <= w.frame.y + w.frame.height
                or values.sibling.frame.x + values.sibling.frame.width < w.frame.x
                or values.sibling.frame.y + values.sibling.frame.height < w.frame.y)
                and sibling_id > window_id then
                table.insert(w.parent.children, table.remove(w.parent.children, window_id))
            end
        end
    elseif values.stack_mode ~= nil then
        local window_id
        for k,v in pairs(w.parent.children) do if v == w then
            window_id = k
            break
        end end
        if window_id == nil then return Error.BadWindow end
        if values.stack_mode == StackMode.Above then
            table.insert(w.parent.children, 1, table.remove(w.parent.children, window_id))
        elseif values.stack_mode == StackMode.Below then
            table.insert(w.parent.children, table.remove(w.parent.children, window_id))
        elseif values.stack_mode == StackMode.TopIf then
            for sibling_id,sibling in pairs(w.parent.children) do
                if (sibling.frame.x <= w.frame.x + w.frame.width
                    or sibling.frame.y <= w.frame.y + w.frame.height
                    or sibling.frame.x + sibling.frame.width < w.frame.x
                    or sibling.frame.y + sibling.frame.height < w.frame.y)
                    and sibling_id < window_id then
                    table.insert(w.parent.children, 1, table.remove(w.parent.children, window_id))
                    break
                end
            end
        elseif values.stack_mode == StackMode.BottomIf then
            for sibling_id,sibling in pairs(w.parent.children) do
                if (sibling.frame.x <= w.frame.x + w.frame.width
                    or sibling.frame.y <= w.frame.y + w.frame.height
                    or sibling.frame.x + sibling.frame.width < w.frame.x
                    or sibling.frame.y + sibling.frame.height < w.frame.y)
                    and sibling_id > window_id then
                    table.insert(w.parent.children, table.remove(w.parent.children, window_id))
                    break
                end
            end
        elseif values.stack_mode == StackMode.Opposite then
            for sibling_id,sibling in pairs(w.parent.children) do
                if (sibling.frame.x <= w.frame.x + w.frame.width
                    or sibling.frame.y <= w.frame.y + w.frame.height
                    or sibling.frame.x + sibling.frame.width < w.frame.x
                    or sibling.frame.y + sibling.frame.height < w.frame.y)
                    and sibling_id < window_id then
                    table.insert(w.parent.children, 1, table.remove(w.parent.children, window_id))
                    break
                elseif (sibling.frame.x <= w.frame.x + w.frame.width
                    or sibling.frame.y <= w.frame.y + w.frame.height
                    or sibling.frame.x + sibling.frame.width < w.frame.x
                    or sibling.frame.y + sibling.frame.height < w.frame.y)
                    and sibling_id > window_id then
                    table.insert(w.parent.children, table.remove(w.parent.children, window_id))
                    break
                end
            end
        end
    end
end

--- Returns the root window for the display.
-- @param display The display to check
-- @return The root window of the display
function CCWinX.DefaultRootWindow(client, display) return display.root end

--- Returns the ID of the screen the display is on.
-- @param display The display to check
-- @return The ID of the screen
function CCWinX.DefaultScreen(client, display) return display.id end

--- Destroys all subwindows of a window.
-- @param display The display for the window
-- @param w The window to destroy the children of
function CCWinX.DestroySubwindows(client, display, w)
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    local delete = {}
    for k,v in pairs(w.children) do delete[k] = v end
    for k,v in pairs(delete) do
        local r = CCWinX.DestroyWindow(v)
        if r then return r end
    end
    w.children = {}
end

--- Destroys a window.
-- @param display The display for the window
-- @param w The window to destroy
function CCWinX.DestroyWindow(client, display, w)
    if type(w) ~= "table" or w.parent == nil then return Error.BadWindow end
    local r = CCWinX.DestroySubwindows(client, display, w)
    if r then return r end
    for k,v in pairs(w.parent.children) do if v == w then
        table.remove(w.parent.children, k)
        break
    end end
    sendEvent("DestroyNotify", false, qs(display), qs(w.parent), qs(w))
    local keys = {}
    for k,v in pairs(w) do table.insert(keys, k) end
    for _,k in pairs(keys) do w[k] = nil end
end

--- Returns the width of a display.
-- @param display The display to check
-- @return The width of the display
function CCWinX.DisplayWidth(client, display) return display.root and display.root.frame.width end

--- Returns the height of a display.
-- @param display The display to check
-- @return The height of the display
function CCWinX.DisplayHeight(client, display) return display.root and display.root.frame.height end

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
            if type(pid) == "number" then
                if ev == "CCWinX.GetServerPID" and type(pid) == "number" then
                    kernel.send(pid, "CCWinX.ServerPID", _PID)
                elseif type(CCWinX[ev]) == "function" then
                    kernel.send(pid, "CCWinX."..ev, CCWinX[ev](pid, table.unpack(args)))
                end
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