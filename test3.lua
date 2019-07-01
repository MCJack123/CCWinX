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
    text_box.display = CCWinX.OpenDisplay("left")
    if not text_box.display then
        error("Could not open display.")
    end
    text_box.root = CCWinX.DefaultRootWindow(text_box.display)
end

local function create_window()
    text_box.width = 300
    text_box.height = 150
    text_box.window = CCWinX.CreateSimpleWindow(text_box.display, text_box.root, 1, 1, text_box.width, text_box.height, 0, colors.black, colors.white)
    assert(type(text_box.window) == "table", CCWinX.ErrorStrings[text_box.window])
    CCWinX.MapWindow(text_box.display, text_box.window)
end

local function set_up_gc()
    text_box.gc = CCWinX.CreateGC(text_box.display, text_box.window, {background = colors.white, foreground = colors.black})
end

local function set_up_font()
    local fontname = "-*-Arial-*-R-*-*-14-*-*-*-*-*-*-*"
    text_box.font = CCWinX.LoadFont(text_box.display, fontname)
    if not text_box.font then
        printError("unable to load font " .. fontname .. ": using fixed")
        text_box.font = CCWinX.LoadFont(text_box.display, "fixed")
    end
    text_box.gc.font = text_box.font
end

local function draw_screen()
    local x, y, direction, ascent, descent, overall = 0, 0, CCWinX.QueryTextExtents(text_box.display, text_box.font, text_box.text)
    assert(type(direction) ~= "number", CCWinX.GetErrorText(nil, direction))
    x = math.floor((text_box.width - overall.width) / 2)
    y = math.floor(text_box.height / 2 + (ascent - descent) / 2)
    CCWinX.ClearWindow(text_box.display, text_box.window)
    local err = CCWinX.DrawString(text_box.display, text_box.window, text_box.gc, x, y, text_box.text)
    assert(err == nil, CCWinX.ErrorStrings[err])
    --CCWinX.Flush(text_box.display)
    text_box.window.draw()
end

local function event_loop()
    while true do
        local e = {os.pullEvent()}
        print(e[1])
        if e[1] == "char" and e[2] == "q" then break 
        elseif e[1] == "char" and e[2] == "r" then draw_screen() end
    end
end

text_box.text = "Hello World!"
print("Connecting...")
x_connect()
print("Creating window...")
create_window()
print("Setting up resources...")
set_up_gc()
set_up_font()
print("Drawing...")
draw_screen()
print("Waiting...")
event_loop()
CCWinX.CloseDisplay(text_box.display)