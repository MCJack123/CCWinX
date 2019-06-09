local _FORK = _FORK
if term.setGraphicsMode == nil then error("CCWinX requires CraftOS-PC v1.2 or later.") end
_ = os.loadAPI("CCLog.lua") or (shell and os.loadAPI(fs.getDir(shell.getRunningProgram()) .. "/CCLog.lua")) or print("CCLog not installed, logging will be disabled.")
local log = CCLog and (CCLog.CCLog and CCLog.CCLog("CCWinX") or CCLog("CCWinX")) or {log = function() end, debug = function() end, info = function() end, warn = function() end, error = function() end, critical = function() end, traceback = function() end, open = function() end, close = function() end}

local CCWinX = {}
local displays = {}

local function qs(tab)
    if (type(tab) ~= "table" and type(tab) ~= "function") or kernel or true then return tab end
    if type(tab) == "function" then return nil end
    local retval = {}
    for k,v in pairs(tab) do retval[qs(k)] = qs(v) end
    return retval
end
local function sendEvent(...) if kernel then kernel.broadcast(...) else os.queueEvent(...) end end

Error = {
    BadColor = 0,
    BadMatch = 1,
    BadValue = 2,
    BadWindow = 3,
    BadDrawable = 4,
}

StackMode = {
    Above = 0,
    Below = 1,
    TopIf = 2,
    BottomIf = 3,
    Opposite = 4
}

Vertex = {
    Relative = 0x01,
    DontDraw = 0x02,
    Curved = 0x04,
    StartClosed = 0x08,
    EndClosed = 0x10
}

GCFunc = {
    GXclear = 0,
    GXand = 1,
    GXandReverse = 2,
    GXcopy = 3,
    GXandInverted = 4,
    GXnoop = 5,
    GXxor = 6,
    GXor = 7,
    GXnor = 8,
    GXequiv = 9,
    GXinvert = 10,
    GXorReverse = 11,
    GXcopyInverted = 12,
    GXorInverted = 13,
    GXnand = 14,
    GXset = 15
}

Line = {
    Solid = 0,
    DoubleDash = 1,
    OnOffDash = 2
}

Cap = {
    NotLast = 0,
    Butt = 1,
    Round = 2,
    Projecting = 3
}

Join = {
    Miter = 0,
    Round = 1,
    Bevel = 2
}

Fill = {
    Solid = 0,
    Tiled = 1,
    OpaqueStippled = 2,
    Stippled = 3
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
        setmetatable(retval, {__index = function(tab, key) return t[key] end})
    elseif type(id) == "number" and id == 0 then
        local native = term.native()
        setmetatable(retval, {__index = function(tab, key) return native[key] end})
    elseif type(id) == "number" and peripheral.isPresent("monitor_" .. (id + 1)) then
        local t = peripheral.wrap("monitor_" .. (id + 1))
        setmetatable(retval, {__index = function(tab, key) return t[key] end})
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
    root.default_color = 0
    root.attributes = {}
    root.border = {}
    root.border.width = 0
    root.border.color = 0
    root.buffer = {}
    root.children = {}
    function root.clear()
        for y = 1, root.frame.height do
            root.buffer[y] = {}
            for x = 1, root.frame.width do
                root.buffer[y][x] = root.default_color
            end
        end
    end
    function root.setPixel(x, y, c) root.buffer[y][x] = c end
    function root.getPixel(x, y) return root.buffer[y][x] end
    function root.drawPixel(x, y, c) retval.setPixel(x, y, c) end
    function root.draw()
        for y,r in pairs(root.buffer) do for x,c in pairs(r) do 
            retval.setPixel(root.frame.x + x - 1, root.frame.y + y - 1, c > 0 and c or retval.getPixel(root.frame.x + x - 1, root.frame.y + y - 1)) 
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
        CCWinX.DestroyWindow(disp.windows[v])
        disp.windows[v] = nil
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
    if x + width > parent.frame.width or y + height > parent.frame.height then
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
        for y = 1, retval.frame.height do
            retval.buffer[y] = {}
            for x = 1, retval.frame.width do
                retval.buffer[y][x] = retval.default_color
            end
        end
    end
    function retval.setPixel(x, y, c) retval.buffer[y][x] = c end
    function retval.getPixel(x, y) return retval.buffer[y][x] end
    function retval.drawPixel(x, y, c) parent.drawPixel(x, y, c) end
    function retval.draw()
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.setPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", client, false, display, parent, retval, x, y, width, height, border_width, retval.attributes.override_redirect)
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
    if type(parent) ~= "table" 
        or parent.default_color == nil 
        or parent.border == nil 
        or parent.border.color == nil 
        or parent.setPixel == nil 
        or parent.children == nil then
        return Error.BadWindow
    end
    if x + width > parent.frame.width or y + height > parent.frame.height then
        return Error.BadValue
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
        for y = 1, retval.frame.height do
            retval.buffer[y] = {}
            for x = 1, retval.frame.width do
                retval.buffer[y][x] = retval.default_color
            end
        end
    end
    function retval.setPixel(x, y, c) retval.buffer[y][x] = c end
    function retval.getPixel(x, y) return retval.buffer[y][x] end
    function retval.drawPixel(x, y, c) parent.drawPixel(x, y, c) end
    function retval.draw()
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.drawPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", client, false, qs(display), qs(parent), qs(retval), x, y, width, height, border_width, retval.attributes.override_redirect)
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
    if exposures then sendEvent("Expose", client, false, qs(display), qs(w), x, y, width, height, 0) end
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

local function copyop(src, dst, func)
    if func == GCFunc.GXclear then return 0
    elseif func == GCFunc.GXand then return bit.band(src, dest)
    elseif func == GCFunc.GXandReverse then return bit.band(src, bit.bnot(dst))
    elseif func == GCFunc.GXcopy then return src
    elseif func == GCFunc.GXandInverted then return bit.band(bit.bnot(src), dst)
    elseif func == GCFunc.GXnoop then return dst
    elseif func == GCFunc.GXxor then return bit.bxor(src, dst)
    elseif func == GCFunc.GXor then return bit.bor(src, dst)
    elseif func == GCFunc.GXnor then return bit.bor(bit.bnot(src), bit.bnot(dst))
    elseif func == GCFunc.GXequiv then return bit.bxor(bit.bnot(src), dst)
    elseif func == GCFunc.GXinvert then return bit.bnot(dst)
    elseif func == GCFunc.GXorReverse then return bit.bor(src, bit.bnot(dst))
    elseif func == GCFunc.GXcopyInverted then return bit.bnot(src)
    elseif func == GCFunc.GXorInverted then return bit.bor(bit.bnot(src), dst)
    elseif func == GCFunc.GXnand then return bit.bor(bit.bnot(src), bit.bnot(dst))
    elseif func == GCFunc.GXset then return 1
    else return src end
end

--- Copies an area between two drawable sources (including windows).
-- @param display The display of the drawables
-- @param src The source drawable to copy from
-- @param dest The destination drawable to copy to
-- @param gc The graphics context to use
-- @param src_x The source X coordinate
-- @param src_y The source Y coordinate
-- @param width The width of the region to copy
-- @param height The height of the region to copy
-- @param dest_x The destination X coordinate
-- @param dest_y The destination Y coordinate
function CCWinX.CopyArea(client, display, src, dest, gc, src_x, src_y, width, height, dest_x, dest_y)
    if type(src) ~= "table" 
        or type(dest) ~= "table" 
        or src.setPixel == nil 
        or src.getPixel == nil 
        or dest.setPixel == nil 
        or dest.getPixel == nil 
        or src.frame == nil 
        or dest.frame == nil then 
        return Error.BadDrawable end
    if src.display ~= display or dest.display ~= display then return Error.BadMatch end
    if src_x + width > src.frame.width or src_y + height > src.frame.height or dest_x + width > dest.frame.width or dest_y + height > dest.frame.height then return Error.BadMatch end
    for y = 1, height do for x = 1, width do
        dest.setPixel(dest_x + x, dest_y + y, copyop(src.getPixel(src_x + x, src_y + y), dest.getPixel(src_x + x, src_y + y), gc["function"]))
    end end
end

--- Creates a new colormap.
-- @param display The display to use
-- @return The new colormap
function CCWinX.CreateColormap(client, display)
    local retval = {}
    for k,v in pairs(colors) do if type(v) == "number" then
        retval[k] = {}
        retval[k].r, retval[k].g, retval[k].b = display.getPaletteColor(v)
        retval[k].r = retval[k].r * 255
        retval[k].g = retval[k].g * 255
        retval[k].b = retval[k].b * 255
    end end
    return retval
end

--- Creates a new graphics context.
-- @param display The display to use
-- @param d The drawable to use
-- @param values Any values to override
-- @return A new graphics context
function CCWinX.CreateGC(client, display, d, values)
    local retval = {
        ["function"] = GCFunc.GXcopy,
        foreground = colors.white,
        background = colors.black,
        line_width = 0,
        line_style = Line.Solid,
        cap_style = Cap.Butt,
        join_style = Join.Miter,
        fill_style = Fill.Solid,
        fill_rule = false,
        arc_mode = false,
        subwindow_mode = false,
        graphics_exposures = True,
        dash_offset = 0,
        dashes = {4, 4}
    }
    for k,v in pairs(values) do retval[k] = v end
    return retval
end

--- Creates a drawable pixmap.
-- @param display The display to use
-- @param d The parent drawable
-- @param width The width of the pixmap
-- @param height The height of the pixmap
-- @return A new pixmap
function CCWinX.CreatePixmap(client, display, d, width, height)
    if width < 1 or height < 1 then return Error.BadValue end
    local retval = {}
    retval.client = client
    retval.display = display
    retval.parent = d
    retval.frame = {}
    retval.frame.x = 0
    retval.frame.y = 0
    retval.frame.width = width
    retval.frame.height = height
    retval.buffer = {}
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
    retval.clear()
    return retval
end

local function rgbtab(num) return {r = bit.brshift(num, 16), g = bit.band(bit.brshift(num, 8), 0xFF), b = bit.band(num, 0xFF)} end

--- Returns the default colormap.
-- @return A colormap with the default colors
function CCWinX.DefaultColormap()
    return {
        white = rgbtab(0xF0F0F0),
        orange = rgbtab(0xF2B233),
        magenta = rgbtab(0xE57FD8),
        lightBlue = rgbtab(0x99B2F2),
        yellow = rgbtab(0xDEDE6C),
        lime = rgbtab(0x7FCC19),
        pink = rgbtab(0xF2B2CC),
        gray = rgbtab(0x4C4C4C),
        lightGray = rgbtab(0x999999),
        cyan = rgbtab(0x4C99B2),
        purple = rgbtab(0xB266E5),
        blue = rgbtab(0x3366CC),
        brown = rgbtab(0x7F664C),
        green = rgbtab(0x57A64E),
        red = rgbtab(0xCC4C4C),
        black = rgbtab(0x191919)
    }
end

CCWinX.DefaultColormapOfScreen = CCWinX.DefaultColormap

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
        local r = CCWinX.DestroyWindow(client, display, v)
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
    sendEvent("DestroyNotify", client, false, qs(display), qs(w.parent), qs(w))
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

--- Draws a polygon or curve from a list of vertices.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param vlist The list of vertices (vertex = table {x, y, flags})

function CCWinX.Draw(client, display, d, vlist)
    if type(d) ~= "table" or type(vlist) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end

end

local function circle_func(w, h, x)
    w=w/2
    h=h/2
    return h + math.sqrt((1 - ((w - x)^2 / w^2)) * h^2),
           h - math.sqrt((1 - ((w - x)^2 / w^2)) * h^2)
end

--- Draws a single arc. (WIP)
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the bounding box
-- @param y The Y coordinate of the bounding box
-- @param width The width of the bounding box
-- @param height The height of the bounding box
-- @param angle1 The start of the arc relative to the three-o'clock position from the center in degrees
-- @param angle2 The number of degrees of the arc relative to the start
function CCWinX.DrawArc(client, display, d, gc, x, y, width, height, angle1, angle2)
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if x + width > d.frame.width or y + height > d.frame.height then return Error.BadMatch end
    if angle2 >= 360 then angle2 = 359.99999999999 end
    local ly1 = height / 2
    local ly2 = height / 2
    for px = 1, width do
        local y1, y2 = circle_func(width, height, px)
        local theta1 = math.deg(math.atan((y1 - (height / 2)) / (px - (width / 2)))) + 90
        local theta2 = math.deg(math.atan((y2 - (height / 2)) / (px - (width / 2)))) + 270
        if theta1 >= angle1 and theta1 < (angle1 + angle2) then
            for py = math.min(ly1, y1), math.max(ly1, y1) do 
                d.setPixel(math.floor(width + x - px), math.floor(y + py), gc.foreground) 
            end
        end
        if theta2 >= angle1 and theta2 < (angle1 + angle2) then 
            for py = math.min(ly2, y2), math.max(ly2, y2) do
                d.setPixel(math.floor(width + x - px), math.floor(y + py), gc.foreground) 
            end
        end
        ly1 = y1
        ly2 = y2
    end
end

--- Draws a list of arcs.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param arcs The list of arcs
function CCWinX.DrawArcs(client, display, d, gc, arcs)
    for k,v in pairs(arcs) do
        local r = CCWinX.DrawArc(client, display, d, gc, v.x, v.y, v.width, v.height, v.angle1, v.angle2)
        if r then return r end
    end
end

--- Draws a single line.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x1 The start X coordinate
-- @param y1 The start Y coordinate
-- @param x2 The end X coordinate
-- @param y2 The end Y coordinate
function CCWinX.DrawLine(client, display, d, gc, x1, y1, x2, y2)
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if x1 > d.frame.width or x2 > d.frame.width or y1 > d.frame.height or y2 > d.frame.height then return Error.BadMatch end
    local dx = x2 - x1
    local dy = y2 - y1
    local de = math.abs(dy / dx)
    local e = 0
    local y = y1
    for x = x1, x2 do
        d.setPixel(x, y, gc.foreground)
        e = e + de
        if e >= 0.5 then
            y = y + (dy < 0 and -1 or 1) * 1
            e = e - 1
        end
    end
end

--- Draws a list of lines.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param lines The list of lines
function CCWinX.DrawLines(client, display, d, gc, lines)
    for k,v in pairs(lines) do
        local r = CCWinX.DrawLine(client, display, d, gc, v.x1, v.y1, v.x2, v.y2)
        if r then return r end
    end
end

--- Draws a single point.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the point
-- @param y The Y coordinate of the point
function CCWinX.DrawPoint(client, display, d, gc, x, y)
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if x > d.frame.width or y > d.frame.height then return Error.BadMatch end
    d.setPixel(x, y, gc.foreground)
end

--- Draws a list of points.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param points The list of points
function CCWinX.DrawPoints(client, display, d, gc, points)
    for k,v in pairs(points) do
        local r = CCWinX.DrawPoint(client, display, d, gc, v.x, v.y)
        if r then return r end
    end
end

--- Draws a rectangle outline.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the rectangle
-- @param y The Y coordinate of the rectangle
-- @param width The width of the rectangle
-- @param height The height of the rectangle
function CCWinX.DrawRectangle(client, display, d, gc, x, y, width, height)
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if x + width > d.frame.width or y + height > d.frame.height then return Error.BadMatch end
    return CCWinX.DrawLines(client, display, d, gc, {
        {x1 = x, y1 = y, x2 = x + width, y2 = y},
        {x1 = x + width, y1 = y, x2 = x + width, y2 = y + height},
        {x1 = x + width, y1 + y + height, x2 = x, y2 = y + height},
        {x1 = x, y1 = y + height, x2 = x, y2 = y}
    })
end

--- Draws a list of rectangles.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param rectangles The list of rectangles
function CCWinX.DrawRectangles(client, display, d, gc, rectangles)
    for k,v in pairs(rectangles) do
        local r = CCWinX.DrawRectangle(client, display, d, gc, v.x, v.y, v.width, v.height)
        if r then return r end
    end
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