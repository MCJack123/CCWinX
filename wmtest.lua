if not os.loadAPI(shell.resolveProgram("CCWinX.lua")) then error("Could not load CCWinX") end
print("Starting")
print(CCWinX.QLength())
while true do
    os.queueEvent("nosleep")
    local e = CCWinX.QLength() > 0 and {CCWinX.PullEvent()} or {os.pullEvent()}
    if e[1] ~= "nosleep" then print(e[1]) end
    if e[1] == "CreateNotify" and e[5].isRootWindow and not e[6].isWMFrame then
        local frame = CCWinX.CreateSimpleWindow(e[4], e[5], e[7] - 1, e[8] - 20, e[9] + 2, e[10] + 21, 0, 0, colors.white)
        frame.isWMFrame = true
        CCWinX.FillRectangle(e[4], frame, {foreground = colors.yellow, background = colors.yellow}, 1, 1, e[9] + 2, 20)
        CCWinX.ReparentWindow(e[4], e[6], frame, 1, 20)
        CCWinX.Flush(e[4])
    elseif e[1] == "DestroyNotify" and e[5].isWMFrame then
        CCWinX.DestroyWindow(e[4], e[5])
    elseif e[1] == "ButtonPress" and e[5].isWMFrame and e[9] < 21 then e[5].dragStart = {x = e[8], y = e[9]}
    elseif e[1] == "ButtonRelease" and e[5].isWMFrame then e[5].dragStart = nil
    elseif e[1] == "MotionNotify" and e[5].isWMFrame and e[5].dragStart ~= nil then 
        CCWinX.MoveWindow(e[4], e[5], e[10] - e[5].dragStart.x, e[11] - e[5].dragStart.y)
        CCWinX.Flush(e[4])
    elseif (e[1] == "char" and e[2] == "q") or (e[1] == "KeyPress" and e[7] == keys.q) or (e[1] == "key" and e[2] == keys.q) then break end
end