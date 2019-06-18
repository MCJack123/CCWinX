--- CCWinX - An Xlib-compatible window manager for CraftOS-PC
-- @release 0.0.1
-- @author JackMacWindows
-- @copyright Copyright 2019 JackMacWindows.

local _FORK = _FORK
if term.setGraphicsMode == nil then error("CCWinX requires CraftOS-PC v1.2 or later.") end
_ = os.loadAPI("CCLog.lua") or (shell and os.loadAPI(fs.getDir(shell.getRunningProgram()) .. "/CCLog.lua")) or print("CCLog not installed, logging will be disabled.")
local log = CCLog and (CCLog.CCLog and CCLog.CCLog("CCWinX") or CCLog("CCWinX")) or {
    log = function() end, 
    debug = function() end, 
    info = function() end, 
    warn = function() end, 
    error = function() end, 
    critical = function() end, 
    traceback = function() end, 
    open = function() end, 
    close = function() end
}

local CCWinX = {}
local displays = {}
fonts = {}
local font_dirs = {"CCWinX/fonts"}
local api_get_dir = nil
local api_get_local = true

-- BDF parser
local function string_split(str, tok)
    words = {}
    for word in str:gmatch(tok) do table.insert(words, word) end
    return words
end

local function string_split_word(text)
    local spat, epat, buf, quoted = [=[^(['"])]=], [=[(['"])$]=]
    local retval = {}
    for str in text:gmatch("%S+") do
        local squoted = str:match(spat)
        local equoted = str:match(epat)
        local escaped = str:match([=[(\*)['"]$]=])
        if squoted and not quoted and not equoted then
            buf, quoted = str, squoted
        elseif buf and equoted == quoted and #escaped % 2 == 0 then
            str, buf, quoted = buf .. ' ' .. str, nil, nil
        elseif buf then
            buf = buf .. ' ' .. str
        end
        if not buf then table.insert(retval, (str:gsub(spat,""):gsub(epat,""))) end
    end
    if buf then log:error("Missing matching quote for " .. buf) end
    return retval
end

local function foreach(func, ...)
    local retval = {}
    for k,v in pairs({...}) do retval[k] = func(v) end
    return table.unpack(retval)
end

local function parseValue(str) 
    local ok, res = pcall(loadstring("return " .. string.gsub(str, "`", "")))
    if not ok then return str else return res end
end

local function parseLine(str)
    local tok = string_split_word(str)
    return table.remove(tok, 1), foreach(parseValue, table.unpack(tok))
end

local propertymap = {
    FOUNDRY = "foundry",
    FAMILY_NAME = "family",
    WEIGHT_NAME = "weight",
    SLANT = "slant",
    SETWIDTH_NAME = "weight_name",
    ADD_STYLE_NAME = "add_style_name",
    PIXEL_SIZE = "pixels",
    POINT_SIZE = "points",
    SPACING = "spacing",
    AVERAGE_WIDTH = "average_width",
    FONT_NAME = "name",
    FACE_NAME = "face_name",
    COPYRIGHT = "copyright",
    FONT_VERSION = "version",
    FONT_ASCENT = "ascent",
    FONT_DESCENT = "descent",
    UNDERLINE_POSITION = "underline_position",
    UNDERLINE_THICKNESS = "underline_thickness",
    X_HEIGHT = "height_x",
    CAP_HEIGHT = "height_cap",
    RAW_ASCENT = "raw_ascent",
    RAW_DESCENT = "raw_descent",
    NORM_SPACE = "normal_space",
    RELATIVE_WEIGHT = "relative_weight",
    RELATIVE_SETWIDTH = "relative_setwidth",
    FIGURE_WIDTH = "figure_width",
    AVG_LOWERCASE_WIDTH = "average_lower_width",
    AVG_UPPERCASE_WIDTH = "average_upper_width"
}

local function ffs(value)
    if value == 0 then return 0 end
    local pos = 0;
    while bit.band(value, 1) == 0 do
        value = bit.blogic_rshift(value, 1);
        pos = pos + 1
    end
    return pos
end

local function readBDFFont(str)
    local retval = {comments = {}, resolution = {}, superscript = {}, subscript = {}, charset = {}, chars = {}}
    local mode = 0
    local ch
    local charname
    local chl = 1
    for line in str:gmatch("[^\n]+") do
        local values = {parseLine(line)}
        local key = table.remove(values, 1)
        if mode == 0 then
            if (key ~= "STARTFONT" or values[1] ~= 2.1) then 
                log:error("Attempted to load invalid BDF font")
                return nil
            else mode = 1 end
        elseif mode == 1 then
            if key == "FONT" then retval.id = values[1]
            elseif key == "SIZE" then retval.size = {px = values[1], x_dpi = values[2], y_dpi = values[3]}
            elseif key == "FONTBOUNDINGBOX" then retval.bounds = {x = values[3], y = values[4], width = values[1], height = values[2]}
            elseif key == "COMMENT" then table.insert(retval.comments, values[1])
            elseif key == "ENDFONT" then return retval
            elseif key == "STARTCHAR" then 
                mode = 3
                charname = values[1]
            elseif key == "STARTPROPERTIES" then mode = 2 end
        elseif mode == 2 then
            if propertymap[key] ~= nil then retval[propertymap[key]] = values[1]
            elseif key == "RESOLUTION_X" then retval.resolution.x = values[1]
            elseif key == "RESOLUTION_Y" then retval.resolution.y = values[1]
            elseif key == "CHARSET_REGISTRY" then retval.charset.registry = values[1]
            elseif key == "CHARSET_ENCODING" then retval.charset.encoding = values[1]
            elseif key == "FONTNAME_REGISTRY" then retval.charset.fontname_registry = values[1]
            elseif key == "CHARSET_COLLECTIONS" then retval.charset.collections = string_split_word(values[1])
            elseif key == "SUPERSCRIPT_X" then retval.superscript.x = values[1]
            elseif key == "SUPERSCRIPT_Y" then retval.superscript.y = values[1]
            elseif key == "SUPERSCRIPT_SIZE" then retval.superscript.size = values[1]
            elseif key == "SUBSCRIPT_X" then retval.subscript.x = values[1]
            elseif key == "SUBSCRIPT_Y" then retval.subscript.y = values[1]
            elseif key == "SUBSCRIPT_SIZE" then retval.subscript.size = values[1]
            elseif key == "ENDPROPERTIES" then mode = 1 end
        elseif mode == 3 then
            if ch ~= nil then
                if charname ~= nil then
                    retval.chars[ch].name = charname
                    charname = nil
                end
                if key == "SWIDTH" then retval.chars[ch].scalable_width = {x = values[1], y = values[2]}
                elseif key == "DWIDTH" then retval.chars[ch].device_width = {x = values[1], y = values[2]}
                elseif key == "BBX" then 
                    retval.chars[ch].bounds = {x = values[3], y = values[4], width = values[1], height = values[2]}
                    retval.chars[ch].bitmap = {}
                    for y = 1, values[2] do retval.chars[ch].bitmap[y] = {} end
                elseif key == "BITMAP" then 
                    mode = 4 
                end
            elseif key == "ENCODING" then 
                ch = string.char(values[1]) 
                retval.chars[ch] = {}
            end
        elseif mode == 4 then
            if key == "ENDCHAR" then 
                ch = nil
                chl = 1
                mode = 1 
            else
                local num = tonumber("0x" .. key)
                --if type(num) ~= "number" then print("Bad number: 0x" .. num) end
                local l = {}
                local w = math.ceil(math.floor(math.log(num) / math.log(2)) / 8) * 8
                for i = ffs(num) or 0, w do l[w-i+1] = bit.band(bit.brshift(num, i-1), 1) == 1 end
                retval.chars[ch].bitmap[chl] = l
                chl = chl + 1
            end
        end
    end
    return retval
end

local function qs(tab)
    if (type(tab) ~= "table" and type(tab) ~= "function") or kernel or true then return tab end
    if type(tab) == "function" then return nil end
    local retval = {}
    for k,v in pairs(tab) do retval[qs(k)] = qs(v) end
    return retval
end

local function sendEvent(...) if kernel then kernel.broadcast(...) else os.queueEvent(...) end end
local function retf(...) return ... end

local function parseBitmap(data, width, height)
    local retval = {}
    local i = 1
    local x = 1
    if width * height / 2 > string.len(data) then return nil end
    while i < width * height / 2 do
        local y = math.floor(x / width) + 1
        if retval[y] == nil then retval[y] = {} end
        retval[y][x] = bit.blshift(1, bit.brshift(bit.band(string.byte(data, i), 0xF0), 4))
        x = x + 1
        y = math.floor(x / width) + 1
        if retval[y] == nil then retval[y] = {} end
        retval[y][x] = bit.blshift(1, bit.band(string.byte(data, i), 0x0F))
        x = x + 1
        i = i + 1
    end
    return retval, width, height
end

local function pcolor(p) return paintutils.parseImage(p)[1][1] end

local function parseBLT(data, width, height)
    local retval = {}
    for y,text in pairs(data[1]) do
        retval[y*3-2] = {}
        retval[y*3-1] = {}
        retval[y*3] = {}
        for x,ch in string.gmatch(text, ".") do
            ch = string.byte(ch)
            if ch < 128 or ch > 159 then
                retval[y*3-2][x*2-1] = 0
                retval[y*3-1][x*2-1] = 0
                retval[y*3][x*2-1] = 0
                retval[y*3-2][x*2] = 0
                retval[y*3-1][x*2] = 0
                retval[y*3][x*2] = 0
            else
                retval[y*3-2][x*2-1] = bit.band(ch, 1) == 1 and pcolor(string.sub(data[2][y], x, x)) or pcolor(string.sub(data[3][y], x, x))
                retval[y*3-2][x*2] = bit.band(ch, 2) == 1 and pcolor(string.sub(data[2][y], x, x)) or pcolor(string.sub(data[3][y], x, x))
                retval[y*3-1][x*2-1] = bit.band(ch, 4) == 1 and pcolor(string.sub(data[2][y], x, x)) or pcolor(string.sub(data[3][y], x, x))
                retval[y*3-1][x*2] = bit.band(ch, 8) == 1 and pcolor(string.sub(data[2][y], x, x)) or pcolor(string.sub(data[3][y], x, x))
                retval[y*3][x*2-1] = bit.band(ch, 16) == 1 and pcolor(string.sub(data[2][y], x, x)) or pcolor(string.sub(data[3][y], x, x))
                retval[y*3][x*2] = pcolor(string.sub(data[3][y], x, x))
            end
        end
    end
    return retval, data.width, data.height
end

local function parseCCG(data, width, height) --[[ TODO: fix this
    local retval_r = {}
    for y,text in pairs(data) do
        retval[y*3-2] = {}
        retval[y*3-1] = {}
        retval[y*3] = {}
        for x,c in string.gmatch(text, ".") do
            ch = string.byte(c.pixelCode)
            if c.useCharacter then
                retval[y*3-2][x*2-1] = 0
                retval[y*3-1][x*2-1] = 0
                retval[y*3][x*2-1] = 0
                retval[y*3-2][x*2] = 0
                retval[y*3-1][x*2] = 0
                retval[y*3][x*2] = 0
            else
                retval[y*3-2][x*2-1] = bit.band(ch, 1) == 1 and c.fgColor or c.bgColor
                retval[y*3-2][x*2] = bit.band(ch, 2) == 1 and c.fgColor or c.bgColor
                retval[y*3-1][x*2-1] = bit.band(ch, 4) == 1 and c.fgColor or c.bgColor
                retval[y*3-1][x*2] = bit.band(ch, 8) == 1 and c.fgColor or c.bgColor
                retval[y*3][x*2-1] = bit.band(ch, 16) == 1 and c.fgColor or c.bgColor
                retval[y*3][x*2] = c.bgColor
            end
        end
    end
    return retval, data.]]
end

local function parseGIF(data, width, height)
    if bbpack == nil then
        log:debug("Attempting to load bbpack API")
        os.loadAPI((api_get_dir or "") .. "bbpack")
        if bbpack == nil then
            if api_get_dir ~= nil then
                local handle = http.get("http://pastebin.com/raw/cUYTGbpb")
                if not handle then
                    log:error("Error downloading bbpack")
                    return nil
                end
                local file = fs.open(fs.combine(api_get_dir, "bbpack.lua"), "w")
                file.write(handle.readAll())
                file.close()
                handle.close()
                os.loadAPI(fs.combine(api_get_dir, "bbpack.lua"))
            elseif api_get_local then
                local handle = http.get("http://pastebin.com/raw/cUYTGbpb")
                if not handle then
                    log:error("Error downloading bbpack")
                    return nil
                end
                local tEnv = {}
                setmetatable( tEnv, { __index = _G } )
                local fnAPI, err = load( handle.readAll(), "bbpack", nil, tEnv )
                if fnAPI then
                    local ok, err = pcall( fnAPI )
                    if not ok then
                        log:error( "Could not load bbpack: " .. err )
                        return nil
                    end
                else
                    log:error( "Could not load bbpack: " .. err )
                    return nil
                end
                
                local tAPI = {}
                for k,v in pairs( tEnv ) do
                    if k ~= "_ENV" then
                        tAPI[k] =  v
                    end
                end

                _G.bbpack = tAPI
            else
                log:error("Could not find bbpack API and downloading is disabled")
                return nil
            end
        end
    end
    if GIF == nil then
        log:debug("Attempting to load GIF API")
        os.loadAPI((api_get_dir or "") .. "GIF")
        if GIF == nil then
            if api_get_dir ~= nil then
                local handle = http.get("http://pastebin.com/raw/5uk9uRjC")
                if not handle then
                    log:error("Error downloading GIF")
                    return nil
                end
                local file = fs.open(fs.combine(api_get_dir, "GIF.lua"), "w")
                file.write(handle.readAll())
                file.close()
                handle.close()
                os.loadAPI(fs.combine(api_get_dir, "GIF.lua"))
            elseif api_get_local then
                local handle = http.get("http://pastebin.com/raw/5uk9uRjC")
                if not handle then
                    log:error("Error downloading GIF")
                    return nil
                end
                local tEnv = {}
                setmetatable( tEnv, { __index = _G } )
                local fnAPI, err = load( handle.readAll(), "GIF", nil, tEnv )
                if fnAPI then
                    local ok, err = pcall( fnAPI )
                    if not ok then
                        log:error( "Could not load GIF: " .. err )
                        return nil
                    end
                else
                    log:error( "Could not load GIF: " .. err )
                    return nil
                end
                
                local tAPI = {}
                for k,v in pairs( tEnv ) do
                    if k ~= "_ENV" then
                        tAPI[k] =  v
                    end
                end

                _G.GIF = tAPI
            else
                log:error("Could not find GIF API and downloading is disabled")
                return nil
            end
        end
    end
    local img
    if fs.exists(data) then img = GIF.loadGIF(data) else
        local name = ".tmp_image_" .. string.gsub(tostring({}), "table: ", "")
        local file = fs.open(name, "w")
        file.write(data)
        file.close()
        img = GIF.loadGIF(name)
        fs.delete(name)
    end
    local retval = {}
    for y,r in pairs(img[1]) do if tonumber(y) ~= nil then
        retval[y] = {}
        local xoff = 0
        for x,c in pairs(r) do if type(c) == "number" then xoff = xoff + c else retval[y][x+xoff] = pcolor(c) end end
    end end
    return retval, img.width, img.height
end

local function parseNFP(data, width, height)
    local retval = paintutils.parseImage(data)
    return retval, #retval[1], #retval
end

local function scaleNFP(data, width, height)
    local img, w, h = paintutils.parseImage(data)
    local retval = {}
    for y,r in pairs(img) do 
        retval[y*9-8] = {}
        for x,c in pairs(r) do for i = 0, 5 do retval[y*9-8][x*6-i] = c end end 
        for i = 0, 7 do retval[y*9-i] = retval[y*9-8] end
    end
    return retval, w*6, h*9
end

local function scaleBLT(data, width, height)
    local img, w, h = parseBLT(data, width, height)
    local retval = {}
    for y,r in pairs(img) do 
        retval[y*3-1] = {}
        for x,c in pairs(r) do 
            retval[y*3-1][x*2-1] = c 
            retval[y*3-1][x*2] = c 
        end
        retval[y*3] = retval[y*3-1]
    end
    return retval, w*2, h*2
end

local function scaleCCG(data, width, height)
    local img, w, h = parseCCG(data, width, height)
    local retval = {}
    for y,r in pairs(img) do 
        retval[y*3-1] = {}
        for x,c in pairs(r) do 
            retval[y*3-1][x*2-1] = c 
            retval[y*3-1][x*2] = c 
        end
        retval[y*3] = retval[y*3-1]
    end
    return retval, w*2, h*2
end

--- Error codes
Error = {
    BadColor = 0, -- Invalid color
    BadMatch = 1, -- Bad match
    BadValue = 2, -- Bad value
    BadWindow = 3, -- Invalid window
    BadDrawable = 4, -- Invalid drawable
    BadName = 5, -- Invalid name
    BadFont = 6, -- Invalid font
    BadGC = 7, -- Invalid gc
}

local ErrorStrings = {
    [Error.BadColor] = "Invalid color",
    [Error.BadMatch] = "Bad match",
    [Error.BadValue] = "Bad value",
    [Error.BadWindow] = "Invalid window",
    [Error.BadDrawable] = "Invalid drawable",
    [Error.BadName] = "Invalid name",
    [Error.BadFont] = "Invalid font",
    [Error.BadGC] = "Invalid graphics context"
}

--- Image formats
-- @see CCWinX.CreateImage
ImageFormat = {
    Bitmap = 0, -- Bitmap image (1 byte = 2 pixels)
    Pixmap = 1, -- Pixmap ([y][x] table)
    NFP = 2, -- Native paint format (scaled)
    BLT = 3, -- BLittle format (scaled)
    GIF = 4, -- Graphics Interchange Format (can be filename)
    CCG = 5, -- CCGraphics format (scaled)
    UnscaledNFP = 6, -- Native paint format (unscaled)
    UnscaledCCG = 7, -- CCGraphics format (unscaled)
    UnscaledBLT = 8 -- BLittle format (unscaled)
}

local ImageFormatConverters = {
    [ImageFormat.Bitmap] = parseBitmap,
    [ImageFormat.Pixmap] = retf,
    [ImageFormat.NFP] = scaleNFP,
    [ImageFormat.BLT] = scaleBLT,
    [ImageFormat.GIF] = parseGIF,
    [ImageFormat.CCG] = scaleCCG,
    [ImageFormat.UnscaledNFP] = parseNFP,
    [ImageFormat.UnscaledCCG] = parseCCG,
    [ImageFormat.UnscaledBLT] = parseBLT
}

--- Stacking mode
StackMode = {
    Above = 0,
    Below = 1,
    TopIf = 2,
    BottomIf = 3,
    Opposite = 4
}

--- Vertex flags
-- @see CCWinX.Draw
Vertex = {
    Relative = 0x01, -- This vertex is relative to the last
    DontDraw = 0x02, -- Don't draw this vertex
    Curved = 0x04, -- This line is curved
    StartClosed = 0x08, -- Start of a closed shape
    EndClosed = 0x10 -- End of a closed shape
}

--- Copy methods
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

--- Line types
Line = {
    Solid = 0, -- Solid line
    DoubleDash = 1, -- Two-color dashed
    OnOffDash = 2 -- Single-color dashed
}

--- Line endings
Cap = {
    NotLast = 0,
    Butt = 1,
    Round = 2,
    Projecting = 3
}

--- Methods to join lines
Join = {
    Miter = 0,
    Round = 1,
    Bevel = 2
}

--- Methods to fill areas
Fill = {
    Solid = 0, -- Solid fill
    Tiled = 1, -- Checkerboard fill
    OpaqueStippled = 2,
    Stippled = 3
}

--- Changes the properties of a graphics context.
-- @param display The display to use
-- @param gc The graphics context to modify
-- @param values The new values
function CCWinX.ChangeGC(client, display, gc, values) for k,v in pairs(values) do gc[k] = v end end

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
        displays[disp.id] = nil
        disp = nil
    end
    return true
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

--- Copies a graphics context.
-- @param display The display to use
-- @param src The source graphics context
-- @param dest The destination graphics context
function CCWinX.CopyGC(client, display, src, dest) for k,v in pairs(src) do dest[k] = v end end

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
        font = 1,
        subwindow_mode = false,
        graphics_exposures = True,
        dash_offset = 0,
        dashes = {4, 4}
    }
    for k,v in pairs(values or {}) do retval[k] = v end
    return retval
end

--- Creates a new image from image data.
-- @param display The display to use
-- @param format The format of the image data
-- @param offset The offset of the image data (string data only)
-- @param data The image data
-- @param width The width of the image
-- @param height The height of the image
-- @return A new image
-- @note You can load in images in bitmap, GIF, and NFP format using a string as data, 
--       and images in pixmap, BLittle, and CCGraphics format using a table as data. 
--       By default NFP, BLittle, and CCGraphics images will be scaled up to native resolutions,
--       use ImageFormat.Unscaled[NFP|BLT|CCG] to skip scaling.
function CCWinX.CreateImage(client, display, format, offset, data, width, height)
    local retval = {}
    if type(data) == "string" and offset ~= nil then data = string.sub(data, offset) end
    retval.data, retval.width, retval.height = ImageFormatConverters[format](data, width, height)
    retval.format = format
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
    retval.default_color = d.default_color
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
    --retval.display = display
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
    function retval.drawPixel(x, y, c) parent.drawPixel(x, y, c == 0 and parent.getPixel(x, y) or c) end
    function retval.draw()
        if not retval.display then return end
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.drawPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
        for k,v in pairs(retval.children) do v.draw() end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", client, false, qs(display), qs(parent), qs(retval), x, y, width, height, border_width, retval.attributes.override_redirect)
    return retval
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
    if type(parent) ~= "table" 
        or parent.default_color == nil 
        or parent.border == nil 
        or parent.border.color == nil 
        or parent.setPixel == nil 
        or parent.children == nil then
        return Error.BadWindow
    end
    local retval = {}
    retval.owner = client
    --retval.display = display
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
    function retval.drawPixel(x, y, c) parent.drawPixel(x, y, c == 0 and parent.getPixel(x, y) or c) end
    function retval.draw()
        if not retval.display then return end
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.drawPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
        for k,v in pairs(retval.children) do v.draw() end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    sendEvent("CreateNotify", client, false, display, parent, retval, x, y, width, height, border_width, retval.attributes.override_redirect)
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

--- Draws a polygon or curve from a list of vertices. (WIP)
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param vlist The list of vertices (vertex = table {x, y, flags})
function CCWinX.Draw(client, display, d, vlist)
    if type(d) ~= "table" or type(vlist) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    local lastx, lasty = 0, 0
    local lastv = table.remove(vlist, 1)
    for _,v in pairs(vlist) do
        local function rel(a, b) return bit.band(v.flags, Vertex.Relative) > 0 and a + b or a end 
        local l
        if bit.band(vlist.flags, Vertex.DontDraw) == 0 then
            if bit.band(vlist.flags, Vertex.Curved) > 0 then
                local angle1 = 0
                if bit.band(v.flags, Vertex.Relative) > 0 then
                    if v.x > 0 and v.y > 0 then angle1 = 90
                    elseif v.x > 0 and v.y < 0 then angle1 = 0
                    elseif v.x < 0 and v.y > 0 then angle1 = 180
                    elseif v.x < 0 and v.y < 0 then angle1 = 270 end
                else
                    if v.x - lastv.x > 0 and v.y - lastv.y > 0 then angle1 = 90
                    elseif v.x - lastv.x > 0 and v.y - lastv.y < 0 then angle1 = 0
                    elseif v.x - lastv.x < 0 and v.y - lastv.y > 0 then angle1 = 180
                    elseif v.x - lastv.x < 0 and v.y - lastv.y < 0 then angle1 = 270 end
                end
                l = CCWinX.DrawArc(client, display, d, gc, 
                    rel(lastv.x, lastx) - (rel(v.x, lastv.x) - rel(lastv.x, lastx)),
                    rel(lastv.y, lasty) - (rel(v.y, lastv.y) - rel(lastv.y, lasty)), 
                    rel(v.x, lastv.x) - rel(lastv.x, lastx), 
                    rel(v.y, lastv.y) - rel(lastv.y, lasty),
                    angle1, 90)
            else
                l = CCWinX.DrawLine(client, display, d, gc, rel(lastv.x, lastx), rel(lastv.y, lasty), rel(v.x, lastv.x), rel(v.y, lastv.y))
            end
        end
        if l then return l end
        lastx, lasty = lastv.x, lastv.y
        lastv = v
    end
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
    if type(gc) ~= "table" or gc.foreground == nil then return Error.BadGC end
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

--- Draws a string using the background and foreground.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the text
-- @param y The Y coordinate of the text
-- @param text The text to write
function CCWinX.DrawImageString(client, display, d, gc, x, y, text)
    if type(gc) ~= "table" or gc.font == nil then return Error.BadGC end
    local err, ascent, descent, overall = CCWinX.QueryTextExtents(client, display, gc.font, text)
    if type(err) == "number" then return err end
    CCWinX.FillRectangle(client, display, d, {foreground = gc.background}, x, y - descent, overall.width, ascent - descent)
    CCWinX.DrawString(client, display, d, gc, x, y, text)
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
    if type(gc) ~= "table" or gc.foreground == nil or gc.line_style == nil or gc.dashes == nil then return Error.BadGC end
    local dx = x2 - x1
    local dy = y2 - y1
    local de = math.abs(dy / dx)
    local e = 0
    local y = y1
    for x = x1, x2 do
        if (gc.line_style == Line.OnOffDash and (x - x1) % (gc.dashes[1] + gc.dashes[2]) > gc.dashes[1]) or gc.line_style == Line.Solid then d.setPixel(x, y, gc.foreground) end
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
    if type(gc) ~= "table" or gc.foreground == nil then return Error.BadGC end
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
    if type(gc) ~= "table" or gc.foreground == nil then return Error.BadGC end
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

--- Draws a string.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the text
-- @param y The Y coordinate of the text
-- @param text The text to draw
function CCWinX.DrawString(client, display, d, gc, x, y, text)
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if type(gc) ~= "table" or gc.foreground == nil or gc.font == nil then return Error.BadGC end
    if fonts[gc.font] == nil then return Error.BadFont end
    local err, ascent, descent, overall = CCWinX.QueryTextExtents(client, display, gc.font, text)
    for c in string.gmatch(text, ".") do
        local fc = fonts[gc.font].chars[c]
        if x + fc.bounds.width + fc.bounds.x > d.frame.width or y + fc.bounds.height + fc.bounds.y > d.frame.height then return Error.BadMatch end
        for py = 1, fc.bounds.height do for px = 1, fc.bounds.width do if fc.bitmap[py][px] then 
            d.setPixel(x + px + fc.bounds.x, y + py - fc.bounds.y - fc.bounds.height + ascent - descent, gc.foreground) 
        end end end
        x = x + fc.device_width.x
    end
end

--- Draws a list of strings.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The initial X coordinate
-- @param y The initial Y coordinate
-- @param items The text items to write
function CCWinX.DrawText(client, display, d, gc, x, y, items)
    local newgc = CCWinX.CreateGC(client, display, d, gc)
    if type(newgc) == "number" then return newgc end
    for _,item in pairs(items) do
        if item.font ~= nil then newgc.font = item.font end
        x = x + item.delta
        local r = CCWinX.DrawString(client, display, d, newgc, x, y, item.chars)
        if r then return r end
    end
end

--- Fills a rectangle.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param x The X coordinate of the rectangle
-- @param y The Y coordinate of the rectangle
-- @param width The width of the rectangle
-- @param height The height of the rectangle
function CCWinX.FillRectangle(client, display, d, gc, x, y, width, height)
    if type(gc) ~= "table" or gc.foreground == nil then return Error.BadGC end
    if type(d) ~= "table" or d.setPixel == nil or d.frame == nil then return Error.BadDrawable end
    if x + width > d.frame.width or y + height > d.frame.height then return Error.BadMatch end
    for py = y, y + height do for px = x, x + width do d.setPixel(px, py, gc.foreground) end end
end

--- Fills a list of rectangles.
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param rectangles The list of rectangles
function CCWinX.FillRectangles(client, display, d, gc, rectangles)
    for k,v in pairs(rectangles) do
        local r = CCWinX.FillRectangle(client, display, d, gc, v.x, v.y, v.width, v.height)
        if r then return r end
    end
end

--- Redraws all windows on a display.
-- @param display The display to redraw
function CCWinX.Flush(client, display) display.root.draw() end

--- Returns a property set on the display's database.
-- @param display The display to use
-- @param program The name of the program
-- @param option The option to get
-- @return The property set, or nil
function CCWinX.GetDefault(client, display, program, option)
    if type(display) ~= "table" then return nil end
    if display.database == nil then display.database = {} end
    return display.database[program] and display.database[program][option]
end

--- Returns a string describing an error code.
-- @param display The display to use
-- @param code The code to check
-- @return The string describing the code
function CCWinX.GetErrorText(client, display, code) return ErrorStrings[code] end

--- Returns a list of paths to scan for fonts.
-- @param display The display to use
-- @return A list of paths for fonts
function CCWinX.GetFontPath() return font_dirs end



--- Loads a font into memory.
-- @param display The display to use
-- @param name The name of the font
-- @return A font ID that can be used with QueryFont
function CCWinX.LoadFont(client, display, name)
    for _,font_dir in pairs(font_dirs) do
        for _,path in pairs(fs.list(font_dir)) do
            local file = fs.open(font_dir .. "/" .. path, "r")
            local font = readBDFFont(file.readAll())
            file.close()
            if font ~= nil and string.find(font.id, string.gsub(string.gsub(string.gsub(name, "-", "%%-"), "?", "."), "*", ".*"), 1, false) then
                local id = #fonts + 1
                fonts[id] = font
                return id
            end
        end
    end
    return nil
end

--- Loads and returns a font.
-- @param display The display to use
-- @param name The name of the font
-- @return A font table
function CCWinX.LoadQueryFont(client, display, name) return fonts[CCWinX.LoadFont(client, display, name) or -1] end

--- Maps a window onto a display.
-- @param display The display to map to
-- @param w The window to map
function CCWinX.MapWindow(client, display, w)
    if type(w) ~= "table" then return Error.BadMatch end 
    w["display"] = display 
    w.draw()
end

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
    root.default_color = colors.black
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
    function root.drawPixel(x, y, c) retval.setPixel(x, y, c == 0 and colors.black or c) end
    function root.draw()
        for y,r in pairs(root.buffer) do for x,c in pairs(r) do 
            retval.setPixel(root.frame.x + x - 1, root.frame.y + y - 1, c > 0 and c or retval.getPixel(root.frame.x + x - 1, root.frame.y + y - 1)) 
        end end
        for k,v in pairs(root.children) do v.draw() end
    end
    root.clear()
    root.draw()
    retval.root = root

    displays[id] = retval
    return retval
end

--- Returns a font that's been loaded with LoadFont.
-- @param display The display to use
-- @param font_ID The ID of the font
-- @return A font table
function CCWinX.QueryFont(client, display, font_ID) return fonts[font_ID] end

--- Returns the extents of a string with a font.
-- @param display The display to use
-- @param font_ID The ID of the font to use
-- @param text The string to check
-- @return The direction (LTR = true), ascent, descent, and overall size table
function CCWinX.QueryTextExtents(client, display, font_ID, text)
    if fonts[font_ID] == nil then return Error.BadFont end
    local direction = fonts[font_ID].slant ~= "R"
    local overall = {lbearing = 0, rbearing = 0, width = 0, ascent = 0, descent = 0}
    for c in string.gmatch(text, ".") do
        local fch = fonts[font_ID].chars[c]
        overall.ascent = math.max(overall.ascent, fch.bounds.y + fch.bounds.height)
        overall.descent = math.min(overall.descent, fch.bounds.y)
        overall.lbearing = math.min(overall.lbearing, fch.bounds.x + overall.width)
        overall.rbearing = math.max(overall.rbearing, fch.bounds.x + fch.bounds.width + overall.width)
        overall.width = overall.width + fch.device_width.x
    end
    return direction, overall.ascent, overall.descent, overall
end

--- Sets the directories to search for font files.
-- @param display The display to use
-- @param directories The directories to search
function CCWinX.SetFontPath(client, display, directories) font_dirs = directories or {"CCWinX/fonts"} end

--- Unloads a previously loaded font.
-- @param display The display to use
-- @param font The font to unload
function CCWinX.UnloadFont(client, display, font) fonts[font] = nil end

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
        log:debug("Reading default font into memory")
        local f = CCWinX.LoadFont(_PID, nil, "-ComputerCraft-CraftOS-Book-R-Mono--9-90-75-75-M-90-ISO8859-1")
        if f == nil then log:error("Could not load default font") end
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
        local f = CCWinX.LoadFont(0, nil, "-ComputerCraft-CraftOS-Book-R-Mono--9-90-75-75-M-90-ISO8859-1")
        if f == nil then log:error("Could not load default font") end
        for k,v in pairs(CCWinX) do _ENV[k] = function(...) return CCWinX[k](0, ...) end end
    end
end