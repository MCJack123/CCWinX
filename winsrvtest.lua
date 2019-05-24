os.loadAPI("CCWinX/winsrv")
local win = winsrv.create("native", math.random(1, 40), math.random(1, 10), 10, 5)
win.setBackgroundColor(bit.blshift(1, math.random(0, 15)))
win.clear()
win.write(...)
while true do
    local ev, p1 = os.pullEvent()
    if ev == "char" and p1 == "q" then break 
    elseif ev == "window_server_closed" and p1 == win.pid then error("Server closed") end
end
winsrv.destroy(win)