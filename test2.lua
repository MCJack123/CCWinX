os.loadAPI("CCWinX/CCWinX.lua")
local dpy = CCWinX.OpenDisplay(0)
assert(dpy)

local w = CCWinX.CreateSimpleWindow(dpy, CCWinX.DefaultRootWindow(dpy), 0, 0,
                200, 100, 0, colors.black, colors.black)
CCWinX.MapWindow(dpy, w)

local gc = CCWinX.CreateGC(dpy, w)
gc.foreground = colors.white

CCWinX.DrawLine(dpy, w, gc, 10, 60, 180, 20)
CCWinX.Flush(dpy)
sleep(10)
CCWinX.CloseDisplay(dpy)