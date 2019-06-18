-- From https://www.lemoda.net/c/xlib-text-box/
os.loadAPI("CCWinX/CCWinX.lua")

local text_box = {
    width = 0,
    height = 0,
    text = "",
    display = nil,
    screen = 0,
    root = nil,
    window = nil,
    gc = nil,
    font = nil
}

local function x_connect()
    text_box.display = CCWinX.OpenDisplay(0)
    if not text_box.display then
        error("Could not open display.")
    end
    text_box.root = CCWinX.DefaultRootWindow(text_box.display)
end

local function create_window()
    text_box.width = 300
    text_box.height = 300
    text_box.window = CCWinX.CreateSimpleWindow(text_box.display, text_box.root, 1, 1, text_box.width, text_box.height, 0, colors.black, colors.white)
    CCWinX.MapWindow(text_box.display, text_box.window)
end

local function set_up_gc()
    text_box.gc = CCWinX.CreateGC(text_box.display, text_box.window)
    text_box.gc.background = colors.white
    text_box.gc.foregound = colors.black
end

local function set_up_font()
    local fontname = "-*-Arial-*-R-*-*-14-*-*-*-*-*-*-*"
    text_box.font = CCWinX.LoadQueryFont(text_box.display, fontname)
    if not text_box.font then
        printError("unable to load font " .. fontname .. ": using fixed")
        text_box.font = CCWinX.QueryFont(1)
    end
    text_box.gc.font = text_box.font.fid
end

local function draw_screen()
    local x, y, direction, ascent, descent, overall = 0, 0,
        CCWinX.QueryTextExtents(text_box.font.fid, text_box.text)
    x = (text_box.width - overall.width) / 2
    y = text_box.height / 2 + (ascent - descent) / 2
    CCWinX.ClearWindow(text_box.display, text_box.window)
    CCWinX.DrawString(text_box.display, text_box.window, text_box.gc, 
        x, y, text_box.text)
    CCWinX.Flush(text_box.display)
end

local function event_loop()
    while true do
        local e = {os.pullEvent()}
        if e[1] == "char" and e[2] == "q" then break end
    end
end

text_box.text = "Hello World"
x_connect()
create_window()
set_up_gc()
set_up_font()
draw_screen()
event_loop()
CCWinX.CloseDisplay(text_box.display)