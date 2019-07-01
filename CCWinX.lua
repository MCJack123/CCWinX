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
local locked_displays = {}
local fonts = {}
local font_dirs = {"CCWinX/fonts"}
local screensaver = {timeout = 900, interval = 0, prefer_blanking = true, allow_exposures = false}
local event_queue = {}
local api_get_dir = nil
local api_get_local = true
local threads_enabled = false

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
-- end BDF parser

-- return arguments
local function retf(...) return ... end

-- parse bitmap to pixmap
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

-- convert color string to color
local function pcolor(p) return paintutils.parseImage(p)[1][1] end

-- parse BLittle to pixmap
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

-- parse CCGraphics to pixmap
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

-- parse GIF to pixmap
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

-- parse paint format to pixmap
local function parseNFP(data, width, height)
    local retval = paintutils.parseImage(data)
    return retval, #retval[1], #retval
end

-- parse paint format to pixmap and scale
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

-- parse BLittle format to pixmap and scale
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

-- parse CCGraphics format to pixmap and scale
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

-- check if display is locked
local function isLocked(display)
    if not threads_enabled then return false end
    for k,v in pairs(locked_displays) do if display.id == v.id and client == v.client then return true end end
    return false
end

-- check what window was hit
local function hitTest(win, x, y)
    for k,v in pairs(win.children) do
        local retval, px, py = hitTest(v, x - win.frame.x, y - win.frame.y)
        if retval then return retval, px, py end
    end
    if x < win.frame.x or y < win.frame.y or x > win.frame.x + win.frame.width or y > win.frame.y + win.frame.height then return nil
    else return win, x, y end
end

local modifiers = 0x0

-- convert CC event to CCWinX event
local function handleEvent(display, ev, ...)
    local argv = {...}
    if display.screensaver_coro ~= nil then
        coroutine.resume(display.screensaver_coro)
        if coroutine.status(display.screensaver_coro) ~= "suspended" then
            display.screensaver_coro = nil
            display.screensaver_timer = os.startTimer(screensaver.timeout)
        end
    end
    if ev == "key" then 
        if argv[1] == keys.leftCtrl or argv[1] == keys.rightCtrl then modifiers = bit.bor(modifiers, 0x1)
        elseif argv[1] == keys.capsLock then modifiers = bit.bxor(modifiers, 0x2)
        elseif argv[1] == keys.leftAlt or argv[1] == keys.rightAlt then modifiers = bit.bor(modifiers, 0x4)
        elseif argv[1] == keys.leftShift or argv[1] == keys.rightShift then modifiers = bit.bor(modifiers, 0x8) end
        CCWinX.QueueEvent(0, "KeyPress", _PID or 0, false, display, os.epoch("utc"), modifiers, argv[1])
    elseif ev == "key_up" then
        if argv[1] == keys.leftCtrl or argv[1] == keys.rightCtrl then modifiers = bit.band(modifiers, bit.bnot(0x1))
        elseif argv[1] == keys.leftAlt or argv[1] == keys.rightAlt then modifiers = bit.band(modifiers, bit.bnot(0x4))
        elseif argv[1] == keys.leftShift or argv[1] == keys.rightShift then modifiers = bit.band(modifiers, bit.bnot(0x8)) end
        CCWinX.QueueEvent(0, "KeyRelease", _PID or 0, false, display, display.root, os.epoch("utc"), modifiers, argv[1])
    elseif ev == "mouse_click" then
        local hit, px, py = hitTest(display.root, argv[2], argv[3])
        CCWinX.QueueEvent(0, "ButtonPress", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.bor(modifiers, bit.blshift(1, argv[1] + 7)), argv[1])
    elseif ev == "mouse_up" then
        local hit, px, py = hitTest(display.root, argv[2], argv[3])
        CCWinX.QueueEvent(0, "ButtonRelease", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.band(modifiers, bit.bnot(bit.blshift(1, argv[1] + 7))), argv[1])
    elseif ev == "mouse_drag" then
        local hit, px, py = hitTest(display.root, argv[2], argv[3])
        CCWinX.QueueEvent(0, "MotionNotify", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.bor(modifiers, bit.blshift(1, argv[1] + 7)), argv[1])
    elseif ev == "mouse_scroll" then
        local hit, px, py = hitTest(display.root, argv[2], argv[3])
        CCWinX.QueueEvent(0, "ButtonPress", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.bor(modifiers, bit.blshift(1, argv[1] / 2 + 11.5)), argv[1])
        CCWinX.QueueEvent(0, "ButtonRelease", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.band(modifiers, bit.bnot(bit.blshift(1, argv[1] / 2 + 11.5))), argv[1])
    elseif ev == "monitor_touch" and argv[1] == display.id then
        argv[1] = 1
        local hit, px, py = hitTest(display.root, argv[2], argv[3])
        CCWinX.QueueEvent(0, "ButtonPress", _PID or 0, false, display, hit, display.root, os.epoch("utc"), px, py, argv[2], argv[3], bit.bor(modifiers, bit.blshift(1, argv[1] + 7)), argv[1])
    elseif ev == "timer" then
        if display.screensaver_timer == args[1] then 
            display.screensaver_timer = nil
            display.screensaver_coro = coroutine.create(CCWinX.ActivateScreenSaver)
            coroutine.resume(display.screensaver_coro, _PID, v, true)
        end
        return
    else return end
    if screensaver.timeout ~= 0 then
        os.cancelTimer(display.screensaver_timer)
        display.screensaver_timer = os.startTimer(screensaver.timeout)
    end
end

-- Beginning of public API

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
    BadImage = 8, -- Invalid image
    WTF = 9999, -- Should never happen
}

local ErrorStrings = {
    [Error.BadColor] = "Invalid color",
    [Error.BadMatch] = "Bad match",
    [Error.BadValue] = "Bad value",
    [Error.BadWindow] = "Invalid window",
    [Error.BadDrawable] = "Invalid drawable",
    [Error.BadName] = "Invalid name",
    [Error.BadFont] = "Invalid font",
    [Error.BadGC] = "Invalid graphics context",
    [Error.BadImage] = "Invalid image",
    [Error.WTF] = "This should never happen",
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

--- Modes to check the number of events in the queue
Queued = {
    Already = 0, -- Number of events already in the queue
    AfterFlush = 1, -- Flushes the output buffer and waits for events
    AfterReading = 2 -- Waits for events
}

--- Button mask
KeyMask = {
    Shift = 0x1,
    Lock = 0x2,
    Control = 0x4,
    Alt = 0x8,
    Mod2 = 0x10,
    Mod3 = 0x20,
    Mod4 = 0x40,
    Mod5 = 0x80,
    Button1 = 0x100,
    Button2 = 0x200,
    Button3 = 0x400,
    Button4 = 0x800,
    Button5 = 0x1000
}

--- Activates the screen saver.
-- This function will block until a keyboard/mouse event occurs, run this in a coroutine to allow background processing.
-- On CCKernel, the server *does* run this in a coroutine.
-- @param display The display to suspend
-- @param no_queue Set to true to not queue events while exposing (use in a coroutine)
function CCWinX.ActivateScreenSaver(client, display, no_queue)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    local w, h = display.getSize()
    if screensaver.prefer_blanking then display.clear()
    elseif screensaver.allow_exposures then
        display.setPixel(math.random(0, w * 6 - 1), math.random(0, h * 9 - 1), bit.blshift(1, math.random(0, 15)))
        if not no_queue then os.queueEvent("nosleep") end
    end
    while true do
        local ev, p1 = os.pullEvent()
        if ev == "key" or ev == "key_up" or string.find(ev, "mouse_") then break 
        elseif ev == "ResetScreenSaver" and p1 == display.id then break end
        if screensaver.prefer_blanking then display.clear()
        elseif screensaver.allow_exposures then
            display.setPixel(math.random(0, w * 6 - 1), math.random(0, h * 9 - 1), bit.blshift(1, math.random(0, 15)))
            if not no_queue then os.queueEvent("nosleep") end
        end
    end
    CCWinX.Flush(client, display)
end

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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.attributes == nil then return Error.BadWindow end
    for k,v in pairs(attributes) do w.attributes[k] = v end
end

--- Checks if an event matching a function is in the queue.
-- @param display The display to use
-- @param predicate The function to call of prototype `function predicate(arg: any, event: table) -> boolean`
-- @param arg An argument to pass to predicate
-- @return Whether a match was found
-- @return The first event that matches
-- @see CCWinX.IfEvent
function CCWinX.CheckIfEvent(client, display, predicate, arg) 
    for k,v in pairs(event_queue) do if predicate(arg, v) then return true, table.remove(event_queue, k) end end 
    return false
end

--- Checks if an event matching any type in a list is in the queue.
-- @param display The display to use
-- @param event_mask A list of events to match
-- @return Whether a match was found
-- @return The event found
-- @see CCWinX.MaskEvent
function CCWinX.CheckMaskEvent(client, display, event_mask)
    for k,v in pairs(event_queue) do for l,w in pairs(event_mask) do if v[1] == w then return true, table.remove(event_queue, k) end end end
    return false
end

--- Checks if an event matching a type is in the queue.
-- @param display The display to use
-- @param event_type The type of event to match
-- @return Whether a match was found
-- @return The event found
-- @see CCWinX.TypedEvent
function CCWinX.CheckTypedEvent(client, display, event_type)
    for k,v in pairs(event_queue) do if v[1] == event_type then return true, table.remove(event_queue, k) end end
    return false
end

--- Checks if an event matching a window and event type is in the queue.
-- @param display The display to use
-- @param w The window to scan for
-- @param event_type The event type to match
-- @return Whether a match was found
-- @return The event found
-- @see CCWinX.TypedWindowEvent
function CCWinX.CheckTypedWindowEvent(client, display, w, event_type)
    for k,v in pairs(event_queue) do if v[1] == event_type then for l,x in pairs(v) do if w == x then return true, table.remove(event_queue, k) end end end end
    return false
end

--- Checks if an event matching a window and event mask is in the queue.
-- @param display The display to use
-- @param w The window to scan for
-- @param event_mask A list of events to allow for, or nil to allow all
-- @return Whether a match was found
-- @return The event that matches
-- @see CCWinX.WindowEvent
function CCWinX.CheckWindowEvent(client, display, w, event_mask)
    for k,v in pairs(event_queue) do
        local good = event_mask ~= nil
        if event_mask ~= nil then for l,x in pairs(event_mask) do if x == v[1] then good = true end end end
        if good then for l,x in pairs(v) do if w == x then return true, table.remove(event_queue, k) end end end
    end
    return false
end

--- Moves the top child of a window to the bottom.
-- @param display The display for the window
-- @param w The window to change the children of
function CCWinX.CirculateSubwindowsDown(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    table.insert(w.children, table.remove(w.children, 1))
    CCWinX.QueueEvent(client, "CirculateNotify", client, false, display, w.parent, w, false)
end

--- Moves the bottom child of a window to the top.
-- @param display The display for the window
-- @param w The window to change the children of
function CCWinX.CirculateSubwindowsUp(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    table.insert(w.children, 1, table.remove(w.children, table.maxn(w.children)))
    CCWinX.QueueEvent(client, "CirculateNotify", client, false, display, w.parent, w, true)
end

--- Moves the bottom or top child of a window to the top or bottom, respectively.
-- @param display The display for the window
-- @param w The window to change the children of
-- @param up Whether to go up (true) or down (false)
function CCWinX.CirculateSubwindows(client, display, w, up)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.frame == nil or w.buffer == nil then return Error.BadWindow end
    if x + width > w.frame.width or y + height > w.frame.height then return Error.BadValue end
    for py = y, y + height do for px = x, x + width do
        w.setPixel(px, py, w.default_color)
    end end
    if exposures then CCWinX.QueueEvent(client, "Expose", client, false, qs(display), qs(w), x, y, width, height, 0) end
end

--- Clears an entire window.
-- @param display The display for the window
-- @param w The window to clear
function CCWinX.ClearWindow(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.clear == nil or w.buffer == nil then return Error.BadWindow end
    w.clear()
end

--- Closes a display object and the windows associated with it.
-- @param disp The display object
-- @return Whether the command succeeded
function CCWinX.CloseDisplay(client, disp)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.frame == nil or w.border == nil or w.parent == nil then return Error.BadWindow end
    if values.x ~= nil or values.y ~= nil or values.border_width ~= nil then
        w.frame.x = values.x or w.frame.x
        w.frame.y = values.y or w.frame.y
        w.border.width = values.border_width or w.border.width
    end
    CCWinX.ResizeWindow(client, display, w, values.width or w.frame.width, values.height or w.frame.height)
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
    CCWinX.QueueEvent(client, "ConfigureNotify", client, false, display, w.parent, w, w.frame.x, w.frame.y, w.frame.width, w.frame.height, w.border.width, values.sibling)
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    if type(display) ~= "table" or display.getPaletteColor == nil then return Error.BadValue end
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
--
-- You can load in images in bitmap, GIF, and NFP format using a string as data, 
-- and images in pixmap, BLittle, and CCGraphics format using a table as data.<br> 
-- By default NFP, BLittle, and CCGraphics images will be scaled up to native resolutions:
-- use ImageFormat.Unscaled[NFP|BLT|CCG] to skip scaling.
-- @param display The display to use
-- @param format The format of the image data
-- @param offset The offset of the image data (string data only)
-- @param data The image data
-- @param width The width of the image
-- @param height The height of the image
-- @return A new image
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    retval.properties = {}
    function retval.clear()
        for y = 1, retval.frame.height do
            retval.buffer[y] = {}
            for x = 1, retval.frame.width do
                retval.buffer[y][x] = retval.default_color
            end
        end
    end
    function retval.setPixel(x, y, c)
        if x % 1 > 0 then error(x, 2) end
        if y % 1 > 0 then error(y, 2) end
        retval.buffer[y][x] = c
    end
    function retval.getPixel(x, y) return retval.buffer[y][x] end
    function retval.drawPixel(x, y, c) parent.drawPixel(retval.frame.x + x, retval.frame.y + y, c == 0 and parent.getPixel(retval.frame.x + x, retval.frame.y + y) or c) end
    function retval.draw()
        if not retval.display then return end
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.drawPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
        for k,v in pairs(retval.children) do v.draw() end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    CCWinX.QueueEvent(client, "CreateNotify", client, false, display, parent, retval, x, y, width, height, border_width)
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    retval.properties = {}
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
    function retval.drawPixel(x, y, c) parent.drawPixel(retval.frame.x + x, retval.frame.y + y, c == 0 and parent.getPixel(retval.frame.x + x, retval.frame.y + y) or c) end
    function retval.draw()
        if not retval.display then return end
        for y,r in pairs(retval.buffer) do for x,c in pairs(r) do 
            parent.drawPixel(retval.frame.x + x - 1, retval.frame.y + y - 1, c > 0 and c or parent.getPixel(retval.frame.x + x, retval.frame.y + y)) 
        end end
        for k,v in pairs(retval.children) do v.draw() end
    end
    retval.clear()
    table.insert(parent.children, 1, retval)
    CCWinX.QueueEvent(client, "CreateNotify", client, false, display, parent, retval, x, y, width, height, border_width)
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

--- Returns the default graphics context.
-- @return The default graphics context
function CCWinX.DefaultGC() return {
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
} end
CCWinX.DefaultGCOfScreen = CCWinX.DefaultGC

--- Returns the root window for the display.
-- @param display The display to check
-- @return The root window of the display
function CCWinX.DefaultRootWindow(client, display) return display.root end
CCWinX.RootWindow = CCWinX.DefaultRootWindow
CCWinX.RootWindowOfScreen = CCWinX.DefaultRootWindow

--- Returns the ID of the screen the display is on.
-- @param display The display to check
-- @return The ID of the screen
function CCWinX.DefaultScreen(client, display) return display.id end

--- Destroys all subwindows of a window.
-- @param display The display for the window
-- @param w The window to destroy the children of
function CCWinX.DestroySubwindows(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.parent == nil then return Error.BadWindow end
    local r = CCWinX.DestroySubwindows(client, display, w)
    if r then return r end
    for k,v in pairs(w.parent.children) do if v == w then
        table.remove(w.parent.children, k)
        break
    end end
    CCWinX.QueueEvent(client, "DestroyNotify", client, false, display, w.parent, w)
    local keys = {}
    for k,v in pairs(w) do table.insert(keys, k) end
    for _,k in pairs(keys) do w[k] = nil end
end

--- Returns the height of a display.
-- @param display The display to check
-- @return The height of the display
function CCWinX.DisplayHeight(client, display) return display.root and display.root.frame.height end

--- Returns the ID of the display.
-- @return The ID passed to CCWinX.OpenDisplay()
function CCWinX.DisplayString(client, display) return type(display) == "table" and display.id end

--- Returns the width of a display.
-- @param display The display to check
-- @return The width of the display
function CCWinX.DisplayWidth(client, display) return display.root and display.root.frame.width end

--- Draws a polygon or curve from a list of vertices. (WIP)
-- @param display The display to use
-- @param d The object to draw on
-- @param gc The graphics context to use
-- @param vlist The list of vertices (vertex = table {x, y, flags})
function CCWinX.Draw(client, display, d, vlist)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    local newgc = CCWinX.CreateGC(client, display, d, gc)
    if type(newgc) == "number" then return newgc end
    for _,item in pairs(items) do
        if item.font ~= nil then newgc.font = item.font end
        x = x + item.delta
        local r = CCWinX.DrawString(client, display, d, newgc, x, y, item.chars)
        if r then return r end
    end
end

--- Returns the number of events in the event queue depending on the mode.
-- @param display The display to use
-- @param mode The mode to use
-- @return The number of events in the queue
-- @see Queued
function CCWinX.EventsQueued(client, display, mode)
    if mode ~= Queued.Already and #event_queue < 1 then
        if mode == Queued.AfterFlush then CCWinX.Flush(display) end
        while #event_queue < 1 do handleEvent(display, os.pullEvent()) end
    end
    return #event_queue
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
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
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    for k,v in pairs(rectangles) do
        local r = CCWinX.FillRectangle(client, display, d, gc, v.x, v.y, v.width, v.height)
        if r then return r end
    end
end

--- Redraws all windows on a display.
-- @param display The display to redraw
function CCWinX.Flush(client, display) 
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    display.root.draw() 
end

--- Either activates or deactivates a screensaver.
-- Will block if activating screen saver, use coroutine to run in background.
-- If deactivating and 
-- @param display The display to set
-- @param mode true to activate, false to deactivate
function CCWinX.ForceScreenSaver(client, display, mode) if mode then CCWinX.ActivateScreenSaver(client, display) else CCWinX.ResetScreenSaver(client, display) end end

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

--- Returns a subimage of a drawable source.
-- @param display The display to use
-- @param d The drawable to copy from
-- @param x The X coordinate of the subimage
-- @param y The Y coordinate of the subimage
-- @param width The width of the subimage
-- @param height The height of the subimage
-- @param plane_mask A bitmask of the colors to copy (default is all/0xFFFF)
function CCWinX.GetImage(client, display, d, x, y, width, height, plane_mask)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    plane_mask = plane_mask or 0xFFFF
    local tmp = CCWinX.CreatePixmap(client, display, d, width, height)
    if type(tmp) == "number" then return tmp end
    return CCWinX.CopyArea(client, display, d, tmp, {["function"] = "copy"}, x, y, width, height, 1, 1) or
        CCWinX.CreateImage(client, display, ImageFormat.Pixmap, nil, tmp.buffer, width, height)
end

--- Returns a pixel in an image.
-- @param ximage The image to check
-- @param x The X coordinate
-- @param y The Y coordinate
-- @return The color of the pixel or nil
-- @return If the first return value is nil, this value is the error code.
function CCWinX.GetPixel(client, ximage, x, y)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(ximage) ~= "table" or ximage.data == nil then return nil, Error.BadImage end
    if ximage.data[y] == nil or ximage.data[y][x] == nil then return nil, Error.BadMatch end
    return ximage.data[y][x]
end

--- Returns the properties of the current screen saver.
-- @return The timeout of the screen saver
-- @return The interval of the screen saver exposure
-- @return Whether to blank the screen
-- @return Whether to display a randomizer screen saver
function CCWinX.GetScreenSaver() return screensaver.timeout, screensaver.interval, screensaver.prefer_blanking, screensaver.allow_exposures end

--- Copies a subimage of a drawable to an existing image.
-- @param display The display to use
-- @param d The drawable to copy from
-- @param x The X coordinate of the subimage
-- @param y The Y coordinate of the subimage
-- @param width The width of the subimage
-- @param height The height of the subimage
-- @param plane_mask A bitmask of the colors to copy (default is all/0xFFFF)
-- @param dest_image The image to copy to
-- @param dest_x The X coordinate of the destination
-- @param dest_y The Y coordinate of the destination
function CCWinX.GetSubImage(client, display, d, x, y, width, height, plane_mask, dest_image, dest_x, dest_y)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    plane_mask = plane_mask or 0xFFFF
    local tmp = CCWinX.CreatePixmap(client, display, d, width, height)
    if type(tmp) == "number" then return tmp end
    local e = CCWinX.CopyArea(client, display, d, tmp, {["function"] = "copy"}, x, y, width, height, 1, 1)
    if e then return e end
    for y,r in pairs(tmp.buffer) do for x,c in pairs(r) do dest_image.data[dest_y+y-1][dest_x+x-1] = c end end
end

--- Calls a function for each event, and returns the first event where the function returns true
-- @param display The display to use
-- @param predicate The function to call of prototype `function predicate(arg: any, event: table) -> boolean`
-- @param arg An argument to pass to predicate
-- @return The first event that matches
function CCWinX.IfEvent(client, display, predicate, arg)
    while true do
        for k,v in pairs(event_queue) do if predicate(arg, v) then return table.remove(event_queue, k) end end
        CCWinX.Flush(client, display)
        handleEvent(display, os.pullEvent())
    end
end

--- Enables multithreading support for the current CCWinX session.
function CCWinX.InitThreads() threads_enabled = true end

--- Sets a colormap onto a display.
-- @param display The display to set
-- @param colormap The colormap to use
function CCWinX.InstallColormap(client, display, colormap, skipevent)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    for k,v in pairs(colors) do display.setPaletteColor(colors[k], v.r / 255, v.g / 255, v.b / 255) end
    if not skipevent then CCWinX.QueueEvent(client, "ColormapNotify", client, false, display, colormap, true) end
end

--- Sends SIGINT to a client using a resource that has a client ID.
-- @param display The display to use
-- @param resource The resource to check
function CCWinX.KillClient(client, display, resource)
    if not kernel then return Error.BadMatch end
    if type(resource) ~= "table" or resource.client == nil then return Error.BadValue end
    kernel.kill(resource.client, signal.SIGINT)
end

--- Returns a list of fonts matching a pattern.
-- @param display The display to use
-- @param pattern The pattern to match
-- @param maxnames The maximum number of names to match (defaults to all)
-- @return A table with a list of matching fonts, or nil if none were found
function CCWinX.ListFonts(client, display, pattern, maxnames)
    if name == "fixed" then name = "-ComputerCraft-CraftOS-Book-R-Mono--9-90-75-75-M-90-ISO8859-1" end
    for k,font in pairs(fonts) do if string.find(font.id, string.gsub(string.gsub(string.gsub(name, "-", "%%-"), "?", "."), "*", ".*"), 1, false) then return k end end
    local retval = nil
    for _,font_dir in pairs(font_dirs) do
        for _,path in pairs(fs.list(font_dir)) do
            local file = fs.open(font_dir .. "/" .. path, "r")
            local font = readBDFFont(file.readAll())
            file.close()
            if font ~= nil and string.find(font.id, string.gsub(string.gsub(string.gsub(name, "-", "%%-"), "?", "."), "*", ".*"), 1, false) then
                if not retval then retval = {} end
                table.insert(retval, font.id)
                if maxnames and #retval >= maxnames then return retval end
            end
        end
    end
    return retval
end

--- Returns a list of property names on a window.
-- @param display The display to use
-- @param w The window to check
-- @return A list of property names
function CCWinX.ListProperties(client, display, w)
    if type(w) ~= "table" or w.properties == nil then return Error.BadWindow end
    local retval = {}
    for k,v in pairs(w.properties) do table.insert(retval, k) end
    return #retval > 0 and retval or nil
end

--- Loads a font into memory.
-- @param display The display to use
-- @param name The name of the font
-- @return A font ID that can be used with QueryFont
function CCWinX.LoadFont(client, display, name)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if name == "fixed" then name = "-ComputerCraft-CraftOS-Book-R-Mono--9-90-75-75-M-90-ISO8859-1" end
    for k,font in pairs(fonts) do if string.find(font.id, string.gsub(string.gsub(string.gsub(name, "-", "%%-"), "?", "."), "*", ".*"), 1, false) then return k end end
    for _,font_dir in pairs(font_dirs) do
        for _,path in pairs(fs.list(font_dir)) do
            local file = fs.open(font_dir .. "/" .. path, "r")
            local font = readBDFFont(file.readAll())
            file.close()
            if font ~= nil and string.find(font.id, string.gsub(string.gsub(string.gsub(name, "-", "%%-"), "?", "."), "*", ".*"), 1, false) then
                local id = #fonts + 1
                font.fid = id
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

--- Locks a display to disallow all other operations on the display.
-- @param display The display to lock
function CCWinX.LockDisplay(client, display)
    if not threads_enabled then return end
    table.insert(locked_displays, {client = client, id = display.id}) 
end

--- Returns the RGB values for 1) a color in a colormap, and 2) the closest color in the screen's colormap
-- @param display The display to use
-- @param colormap The colormap to use
-- @param color_name The name or color value of the color
-- @return The RGB values of the color
-- @return The RGB values of the color closest to return value #1 in the current colormap
function CCWinX.LookupColor(client, display, colormap, color_name)
    if type(color_name) == "number" then for k,v in pairs(colors) do if v == color_name then color_name = k end end end
    if colormap[color_name] == nil then return Error.BadColor end
    local nearest_color, nearest_distance = nil, math.huge
    local cmap = CCWinX.CreateColormap(client, display)
    for k,v in pairs(cmap) do
        local distance = math.abs(colormap[color_name].r - v.r)^2 + math.abs(colormap[color_name].g - v.g)^2 + math.abs(colormap[color_name].b - v.b)^2
        if distance < nearest_distance then
            nearest_distance = distance
            nearest_color = v
        end
    end
    return colormap[color_name], nearest_color
end

--- Moves a window to the bottom of the parent's stack.
-- @param display The display to use
-- @param w The window to lower
function CCWinX.LowerWindow(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.parent == nil or w.parent.children == nil then return Error.BadWindow end
    for k,v in pairs(w.parent.children) do if v == w then
        table.remove(w.parent.children, k)
        break
    end end
    table.insert(w.parent.children, w)
end

--- Maps and raises a window.
-- @param display The display to use
-- @param w The window to map and raise
function CCWinX.MapRaised(client, display, w) return CCWinX.RaiseWindow(client, display, w) or CCWinX.MapWindow(client, display, w) end

--- Maps all subwindows of a window.
-- @param display The display to use
-- @param w The window to map the subwindows of
function CCWinX.MapSubwindows(client, display, w) for k,v in w.children do CCWinX.MapWindow(client, display, v) end end

--- Maps a window onto a display.
-- @param display The display to map to
-- @param w The window to map
function CCWinX.MapWindow(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" then return Error.BadMatch end 
    w.display = display 
    w.draw()
    CCWinX.QueueEvent(client, "MapNotify", client, false, display, w.parent, w)
end

--- Waits for an event matching any type in a list to be queued.
-- @param display The display to use
-- @param event_mask A list of events to match
-- @return The event found
function CCWinX.MaskEvent(client, display, event_mask)
    while true do
        for k,v in pairs(event_queue) do for l,w in pairs(event_mask) do if v[1] == w then return table.remove(event_queue, k) end end end
        CCWinX.Flush(client, display)
        handleEvent(display, os.pullEvent())
    end
end

--- Moves and resizes a window.
-- @param display The display to use
-- @param w The window to modify
-- @param x The new X coordinate of the window
-- @param y The new Y coordinate of the window
-- @param width The new width of the window
-- @param height The new height of the window
function CCWinX.MoveResizeWindow(client, display, w, x, y, width, height) return CCWinX.MoveWindow(client, display, w, x, y) or CCWinX.ResizeWindow(client, display, w, width, height) end

--- Moves a window.
-- @param display The display to use
-- @param w The window to modify
-- @param x The new X coordinate of the window
-- @param y The new Y coordinate of the window
function CCWinX.MoveWindow(client, display, w, x, y)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.frame == nil or w.draw == nil then return Error.BadWindow end
    w.frame.x = x
    w.frame.y = y
end

--- Returns the next event in the queue.
-- @return The next event in the queue
function CCWinX.NextEvent() return table.remove(event_queue, 1) end

--- Does nothing.
-- @param display The display to use
function CCWinX.NoOp(client, display) while isLocked(client, display) do handleEvent(display, os.pullEvent()) end end

local function tonum_rep(str, ...) if str ~= nil then return tonumber(str), tonum_rep(...) end end

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
    root.owner = _PID
    root.isRootWindow = true
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

--- Parses a geometry string in the form of [=][<width>{xX}<height>][{+-}<xoffset>{+-}<yoffset>].
-- @param parsestring The string to parse
-- @return The X offset
-- @return The Y offset
-- @return The width
-- @return The height
function CCWinX.ParseGeometry(client, parsestring)
    local x, y = tonum_rep(string.match(parsestring, "([+-]%d+)([+-]%d+)"))
    return x, y, tonum_rep(string.match(parsestring, "=?(%d+)[xX](%d+)"))
end

--- Returns the next event in the queue without removing it.
-- @return The next event in the queue
function CCWinX.PeekEvent() return event_queue[1] end

--- Calls a function for each event, and returns the first event where the function returns true without removing it from the queue
-- @param display The display to use
-- @param predicate The function to call of prototype `function predicate(arg: any, event: table) -> boolean`
-- @param arg An argument to pass to predicate
-- @return The first event that matches
function CCWinX.PeekIfEvent(client, display, predicate, arg)
    while true do
        for k,v in pairs(event_queue) do if predicate(arg, v) then return v end end
        CCWinX.Flush(client, display)
        handleEvent(display, os.pullEvent())
    end
end

--- Returns the X protocol version implemented by CCWinX.
function CCWinX.ProtocolVersion() return 11 end

--- Returns the X protocol revision implemented by CCWinX.
function CCWinX.ProtocolRevision() return 6 end

--- Returns the next event in the queue with syntax similar to os.pullEvent.
-- @param mask The event type to match, or nil
-- @return The type of event
-- @return Each argument in the event
function CCWinX.PullEvent(client, mask)
    while true do
        if #event_queue > 0 then
            local ev = table.remove(event_queue, 1)
            if mask == nil or mask == ev[1] then return table.unpack(ev) end
        end
        local e = {os.pullEvent()}
        if mask == nil or mask == e[1] then return table.unpack(e) end
    end
end

--- Places an event back at the beginning of the queue.
-- @param display The display to use
-- @param event The event to put back
function CCWinX.PutBackEvent(client, display, event) table.insert(event_queue, 1, event) end

--- Draws an image onto a drawable.
-- @param display The display to use
-- @param d The drawable to draw on
-- @param gc The graphics context to use
-- @param image The image to draw
-- @param src_x The X offset in the image
-- @param src_y The Y offset in the image
-- @param dest_x The X coordinate to draw at
-- @param dest_y The Y coordinate to draw at
-- @param width The width of the subimage to draw
-- @param height The height of the subimage to draw
function CCWinX.PutImage(client, display, d, gc, image, src_x, src_y, dest_x, dest_y, width, height)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(d) ~= "table" or d.setPixel == nil or d.getPixel == nil or d.frame == nil then return Error.BadDrawable end
    if type(gc) ~= "table" or gc.background == nil then return Error.BadGC end
    if type(image) ~= "table" or image.data == nil or image.width == nil or image.height == nil then return Error.BadImage end
    if src_x < 1 or src_y < 1 or src_x + width > image.width or src_y + height > image.height or dest_x + width > d.frame.width or dest_y + height > d.frame.height then return Error.BadMatch end
    for y = 1, height do for x = 1, width do
        local c = image.data[src_y+y][src_x+x] or 0
        if c == 0 then c = d.getPixel(dest_x + x, dest_y + y) end
        d.setPixel(dest_x + x, dest_y + y, copyop(d.getPixel(dest_x + x, dest_y + y), c))
    end end
end

--- Sets a pixel in an image.
-- @param ximage The image to modify
-- @param x The X coordinate of the pixel
-- @param y The Y coordinate of the pixel
-- @param pixel The value to set to
function CCWinX.PutPixel(client, ximage, x, y, pixel) ximage.data[y][x] = pixel end

--- Returns the number of events in the queue.
-- @return The number of events in the queue
function CCWinX.QLength() return #event_queue end

--- Returns the RGB values for a color value.
-- @param display The display to use
-- @param colormap The colormap to check
-- @param color The color to check
-- @return The RGB values of the color
function CCWinX.QueryColor(client, display, colormap, color)
    local color_name = nil
    for k,v in pairs(colors) do if v == color then color_name = k end end
    if not color_name then return Error.BadColor end
    return colormap[color_name] or Error.BadColor
end

--- Returns a list of RGB values for a list of color values.
-- @param display The display to use
-- @param colormap The colormap to check
-- @param colors_in The colors to check
-- @return The RGB values of each color
function CCWinX.QueryColors(client, display, colormap, colors_in)
    local retval = {}
    for k,v in pairs(colors_in) do table.insert(retval, CCWinX.QueryColor(client, display, colormap, v)) end
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
-- @return The direction (LTR = true)
-- @return Ascent
-- @return Descent
-- @return Overall size table
function CCWinX.QueryTextExtents(client, display, font_ID, text)
    if fonts[font_ID] == nil then return Error.BadFont end
    local direction = fonts[font_ID].slant ~= "R"
    local overall = {lbearing = 0, rbearing = 0, width = 0, ascent = 0, descent = 0}
    for c in string.gmatch(text, ".") do
        local fch = fonts[font_ID].chars[c]
        overall.ascent = math.floor(math.max(overall.ascent, fch.bounds.y + fch.bounds.height))
        overall.descent = math.floor(math.min(overall.descent, fch.bounds.y))
        overall.lbearing = math.floor(math.min(overall.lbearing, fch.bounds.x + overall.width))
        overall.rbearing = math.floor(math.max(overall.rbearing, fch.bounds.x + fch.bounds.width + overall.width))
        overall.width = math.floor(overall.width + fch.device_width.x)
    end
    return direction, overall.ascent, overall.descent, overall
end
CCWinX.TextExtents = CCWinX.QueryTextExtents

--- Queues an event using a syntax similar to os.queueEvent.
-- @param type The event type
-- @param ... The event arguments
function CCWinX.QueueEvent(client, type, ...) table.insert(event_queue, {type, ...}) end

--- Raises a window to the top of the parent's stack.
-- @param display The display to use
-- @param w The window to raise
function CCWinX.RaiseWindow(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.parent == nil or w.parent.children == nil then return Error.BadWindow end
    for k,v in pairs(w.parent.children) do if v == w then
        table.remove(w.parent.children, k)
        break
    end end
    table.insert(w.parent.children, 1, w)
end

--- Changes the parent of a window.
-- @param display The display to use
-- @param w The window to reparent
-- @param parent The new parent window
-- @param x The new X coordinate inside the parent
-- @param y The new Y coordinate inside the parent
function CCWinX.ReparentWindow(client, display, w, parent, x, y)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or type(parent) ~= "table" or w.frame == nil or parent.frame == nil or w.parent == nil then return Error.BadWindow end
    for k,v in pairs(w.parent.children) do if v == w then
        table.remove(w.parent.children, k)
        break
    end end
    local old_parent = w.parent
    local mapped = w.display ~= nil
    if mapped then CCWinX.UnmapWindow(client, display, w) end
    table.insert(parent.children, 1, w)
    w.parent = parent
    w.frame.x = x
    w.frame.y = y
    CCWinX.QueueEvent(client, "ReparentNotify", client, false, display, old_parent, w, parent, x, y)
    if mapped then CCWinX.MapWindow(client, display, w) end
end

--- Resets the screen saver.
-- @param display The display to set
function CCWinX.ResetScreenSaver(client, display)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if kernel then kernel.broadcast("ForceScreenSaverReset", display.id) else os.queueEvent("ForceScreenSaverReset", display.id) end
    handleEvent(display, os.pullEvent())
end

--- Resizes a window.
-- @param display The display to use
-- @param w The window to resize
-- @param width The new width of the window
-- @param height The new height of the window
function CCWinX.ResizeWindow(client, display, w, width, height)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.frame == nil or w.parent == nil or w.buffer == nil then return Error.BadWindow end
    if height > w.frame.height then
        for y = w.frame.height + 1, height do
            w.buffer[y] = {}
            for x = 1, w.frame.width do
                w.buffer[y][x] = w.default_color
            end
        end
    elseif height < w.frame.height then
        for y = height + 1, w.frame.height do w.buffer[y] = nil end
    end
    w.frame.height = height
    if width > w.frame.width then
        for y = 1, w.frame.height do
            for x = w.frame.width + 1, width do
                w.buffer[y][x] = w.default_color
            end
        end
    elseif width < w.frame.width then
        for y = 1, w.frame.height do
            for x = width + 1, w.frame.width do
                w.buffer[y][x] = nil
            end
        end
    end
    w.frame.width = width
end

--- Restacks a list of windows from top to bottom.
-- @param display The display to use
-- @param windows The windows to restack
function CCWinX.RestackWindows(client, display, windows)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(windows) ~= "table" or #windows < 1 then return Error.BadValue end
    if type(windows[1]) ~= "table" or windows[1].parent == nil then return Error.BadWindow end
    for k,v in pairs(windows) do if type(v) ~= "table" or v.parent == nil then return Error.BadWindow elseif v.parent ~= windows[1].parent then return Error.BadMatch end end
    local win_base
    local children = windows[1].parent.children
    for k,v in pairs(children) do if v == windows[1] then win_base = k end end
    if not win_base then return Error.WTF end
    for k,v in pairs(windows) do if k > 1 then for l,w in pairs(children) do if w == v then 
        table.remove(children, l)
        table.insert(children, win_base + k - 1, v)
        break
    end end end end
end

--- Adds an event to the end of the queue.
-- @param display The display to use
-- @param event The event to add
function CCWinX.SendEvent(client, display, event) table.insert(event_queue, event) end

--- Sets the directories to search for font files.
-- @param display The display to use
-- @param directories The directories to search
function CCWinX.SetFontPath(client, display, directories) font_dirs = directories or {"CCWinX/fonts"} end

--- Sets the properties of the screen saver.
-- @param display The display
-- @param timeout The number of seconds to wait for screen saver (CCKernel2 only)
-- @param interval The number of seconds between alterations
-- @param prefer_blanking Whether to blank the screen for the screen saver
-- @param allow_exposures Whether to activate randomizer screen saver
function CCWinX.SetScreenSaver(client, display, timeout, interval, prefer_blanking, allow_exposures)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if timeout == -1 then timeout = 900
    elseif timeout < 0 then return Error.BadValue end
    screensaver = {timeout = timeout, interval = interval, prefer_blanking = prefer_blanking, allow_exposures = allow_exposures}
end

--- Creates a subimage of another image.
-- @param ximage The image to subimage
-- @param x The X coordinate of the subimage
-- @param y The Y coordinate of the subimage
-- @param width The width of the subimage
-- @param height The height of the subimage
-- @return A new image with the contents of a rectange in the original
function CCWinX.SubImage(client, ximage, x, y, width, height)
    if type(ximage) ~= "table" or ximage.data == nil or ximage.width == nil or ximage.height == nil then return Error.BadImage end
    if x + width > ximage.width or y + height > ximage.height or x < 1 or y < 1 then return Error.BadMatch end
    local retval = {}
    retval.width = width
    retval.height = height
    retval.format = ximage.format
    retval.data = {}
    for py = y, y + height - 1 do
        retval.data[py-y+1] = {}
        for px = x, x + width - 1 do retval.data[py-y+1][px-x+1] = ximage.data[py][px] end
    end
    return retval
end

--- Flushes the output buffer to the display.
-- @param display The display to flush
-- @param discard Whether to discard all events in the queue (defaults to false)
function CCWinX.Sync(client, display, discard)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    display.root.draw()
    if discard then event_queue = {} end
end

--- Returns the width of a string.
-- @param font_struct The font to use
-- @param str The string to check
-- @return The width of the string in pixels
function CCWinX.TextWidth(client, font_struct, str)
    if type(font_struct) ~= "table" or font_struct.slant == nil or font_struct.chars == nil then return Error.BadFont end
    local width = 0
    for c in string.gmatch(text, ".") do width = math.floor(width + font_struct.chars[c].device_width.x) end
    return width
end

--- Translates the coordinates in one window to coordinates in another window.
-- @param display The display to use
-- @param src_w The source window
-- @param dest_w The destination window
-- @param src_x The source X coordinate
-- @param src_y The source Y coordinate
-- @return The destination X coordinate (nil on error)
-- @return The destination Y coordinate
-- @return Whether the destination is a child of the source
function CCWinX.TranslateCoordinates(client, display, src_w, dest_w, src_x, src_y)
    if type(src_w) ~= "table" or type(dest_w) ~= "table" or src_w.frame == nil or dest_w.frame == nil then return nil, Error.BadWindow end
    if src_w.display ~= display or dest_w.display ~= display then return nil, Error.BadMatch end
    local win = src_w
    local sx, sy = src_x, src_y
    while win ~= display.root do
        if win == dest_w then return sx, sy, true end
        sx = sx + win.frame.x
        sy = sy + win.frame.y
        win = win.parent
    end
    local dx, dy = 0, 0
    win = dest_w
    while dest_w ~= display.root do
        if win == src_w then return dx + src_x, dy + dest_y, false end
        dx = dx + win.frame.x
        dy = dy + win.frame.y
        win = win.parent
    end
    return dx - sx, dy - sy, false
end

--- Resets the colormap on a display.
-- @param display The display to modify
-- @param colormap The colormap to uninstall
function CCWinX.UninstallColormap(client, display, colormap)
    CCWinX.InstallColormap(client, display, CCWinX.DefaultColormap(), true)
    CCWinX.QueueEvent(client, "ColormapNotify", client, false, display, colormap, false)
end

--- Unloads a previously loaded font.
-- @param display The display to use
-- @param font The font to unload
function CCWinX.UnloadFont(client, display, font) fonts[font] = nil end

--- Unlocks a previously locked display.
-- @param display The display to unlock
function CCWinX.UnlockDisplay(client, display)
    if not threads_enabled then return end
    for k,v in pairs(locked_displays) do if client == v.client and display.id == v.id then
        locked_displays[k] = nil
        return
    end end
end

--- Unmaps all subwindows of a window.
-- @param display The display to use
-- @param w The window to unmap the subwindows of
function CCWinX.UnmapSubwindows(client, display, w)
    if type(w) ~= "table" or w.children == nil then return Error.BadWindow end
    for k,v in pairs(w.children) do CCWinX.UnmapWindow(client, display, v) end
end

--- Unmaps a window from a display.
-- @param display The display to use
-- @param w The window to unmap
function CCWinX.UnmapWindow(client, display, w)
    while isLocked(client, display) do handleEvent(display, os.pullEvent()) end
    if type(w) ~= "table" or w.parent == nil then return Error.BadWindow end
    w.display = nil
    w.parent.draw()
    CCWinX.QueueEvent(client, "UnmapNotify", client, false, display, w.parent, w, false)
end

--- Waits until an event matching a window and event mask is queued.
-- @param display The display to use
-- @param w The window to scan for
-- @param event_mask A list of events to allow for, or nil to allow all
-- @return The event that matches
function CCWinX.WindowEvent(client, display, w, event_mask)
    while true do
        for k,v in pairs(event_queue) do
            local good = event_mask ~= nil
            if event_mask ~= nil then for l,x in pairs(event_mask) do if x == v[1] then good = true end end end
            if good then for l,x in pairs(v) do if w == x then return table.remove(event_queue, k) end end end
        end
        CCWinX.Flush(client, display)
        handleEvent(display, os.pullEvent())
    end
end

-- If run under CCKernel2 through a shell or forked: start a CCWinX server to listen to clients
-- If loaded as an API under CCKernel2: provide functions to send messages to a CCWinX server
-- If run without CCKernel2 through a shell: do nothing
-- If loaded as an API without CCKernel2: provide functions to run a server

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
            for k,v in pairs(displays) do handleEvent(v, table.unpack(args)) end
            local ev = table.remove(args, 1)
            local pid = table.remove(args, 1)
            if type(pid) == "number" then
                if ev == "CCWinX.GetServerPID" and type(pid) == "number" then
                    kernel.send(pid, "CCWinX.ServerPID", _PID)
                elseif type(CCWinX[ev]) == "function" then
                    kernel.send(pid, "CCWinX."..ev, CCWinX[ev](pid, table.unpack(args)))
                end
            end
            
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