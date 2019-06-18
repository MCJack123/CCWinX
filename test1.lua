os.loadAPI("CCWinX/CCWinX.lua")
local dpy = CCWinX.OpenDisplay(0)
assert(dpy)
local w = CCWinX.CreateWindow(dpy, CCWinX.DefaultRootWindow(dpy), 0, 0,
                    200, 100, 0, 0, {})
assert(type(w) == "table", CCWinX.GetErrorText(dpy, w))
w.default_color = colors.lightGray
CCWinX.ClearWindow(dpy, w)
assert(CCWinX.MapWindow(dpy, w) == nil)
assert(CCWinX.Flush(dpy) == nil)
sleep(10)
CCWinX.CloseDisplay(dpy)