# CCWinX
CCWinX is an API for CraftOS-PC that adds X-style windowing using graphics mode. It's designed to be mostly compatible with the Xlib API, and many programs written with Xlib can be ported to CCWinX with little trouble.

## Requirements
- [CraftOS-PC](https://github.com/MCJack123/craftos) v1.2 or later (or the compatible [ComputerCraft fork](https://github.com/MCJack123/ComputerCraft))
### Optional
- CCLog (for enhanced logging)
- [CCKernel2](https://github.com/MCJack123/CCKernel2) (to allow multiple programs on one server)

## Usage
### Base CraftOS
Simply load the CCWinX API to use the functions in a program.
### CCKernel2
CCKernel2 requires that the server is started as a separate process. You can press Ctrl-Alt-2 to switch to an alternate VT, login, and run CCWinX. Then you can press Ctrl-Alt-1 to switch back to the original VT and run a client.

## Getting Started
```lua
if not os.loadAPI("CCWinX.lua") then error("Could not load CCWinX") end -- load CCWinX
local display = CCWinX.OpenDisplay(0) -- open main display
local win = CCWinX.CreateSimpleWindow(display, CCWinX.DefaultRootWindow(display), 10, 10, 100, 60, 0, 0, colors.white) -- create 100x60 window
CCWinX.FillRectangle(display, win, {foreground = colors.yellow}, 5, 5, 30, 20) -- fill rectangle with yellow
CCWinX.DrawString(display, win, {font = CCWinX.LoadFont(display, "fixed")}, 5, 30, "Hello!") -- draw "Hello!" on screen
CCWinX.MapWindow(display, win) -- map window to display
sleep(5) -- wait 5 seconds
CCWinX.CloseDisplay(display) -- close display
```

## Documentation
The documentation is built with LDoc and available on [GitHub Pages](https://mcjack123.github.io/CCWinX/).