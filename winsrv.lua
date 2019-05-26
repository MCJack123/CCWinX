if shell then
    local windows = {}
    term.clear()
    term.setCursorPos(1, 1)
    if ({...})[1] ~= nil then kernel.exec(shell.resolveProgram(({...})[1])) end
    while true do
        local args = {os.pullEvent()}
        local ev = table.remove(args, 1)
        if ev == "window_create" then
            local pid = table.remove(args, 1)
            local k = table.maxn(windows) + 1
            if args[1] == "native" then args[1] = term.current() end
            if #args < 5 then kernel.send(pid, "window_create_response", nil) else
                local v = window.create(table.unpack(args))
                v.parent = args[1]
                v.pid = pid
                windows[k] = v
                local retval = {id = k, pid = _PID}
                for j,l in pairs(v) do if type(l) == "function" then retval[j] = function(...)
                    kernel.send(retval.pid, "window_event", _G._PID, k, j, ...)
                    while true do
                        local argv = {os.pullEvent()}
                        if table.remove(argv, 1) == "window_event_response" and table.remove(argv, 1) == k and table.remove(argv, 1) == j then return table.unpack(argv) end
                    end
                end end end
                kernel.send(pid, "window_create_response", retval)
            end
        elseif ev == "window_server" then
            kernel.send(args[1], "window_server_response", _PID)
        elseif ev == "window_event" then
            local pid = table.remove(args, 1)
            local id = table.remove(args, 1)
            local ev = table.remove(args, 1)
            local retval = {}
            if type(windows[id]) == "table" and type(windows[id][ev]) == "function" then retval = {windows[id][ev](table.unpack(args))} end
            kernel.send(pid, "window_event_response", id, ev, table.unpack(retval))
        elseif ev == "window_destroy" then
            local win = windows[args[1]]
            win.setBackgroundColor(win.parent.getBackgroundColor())
            win.setTextColor(win.parent.getTextColor())
            win.clear()
            win.setVisible(false)
            windows[args[1]] = nil
            for k,v in pairs(windows) do v.redraw() end
        elseif ev == "char" and args[1] == "q" then break end
    end
    local pids = {}
    for k,win in pairs(windows) do
        win.setBackgroundColor(win.parent.getBackgroundColor())
        win.setTextColor(win.parent.getTextColor())
        win.clear()
        win.setVisible(false)
        local f = false
        for _,p in pairs(pids) do if p == win.pid then f = true end end
        if not p then table.insert(pids, win.pid) end
    end
    for _,p in pairs(pids) do kernel.send(p, "window_server_closed", _PID) end
else
    local server_pid = nil
    function _ENV.create(parentTerm, x, y, width, height, visible)
        if server_pid == nil then
            kernel.broadcast("window_server", _PID)
            os.pullEvent()
            local ev, pid = os.pullEvent()
            if ev ~= "window_server_response" then error("Could not find server: " .. ev, 2) end
            server_pid = pid
        end
        kernel.send(server_pid, "window_create", _PID, parentTerm, x, y, width, height, visible)
        local retval = ({os.pullEvent("window_create_response")})[2]
        return retval
    end
    function _ENV.destroy(win)
        if type(win) ~= "table" or win.id == nil then error("Invalid window", 2) end
        if server_pid == nil then
            kernel.broadcast("window_server", _PID)
            os.pullEvent()
            local ev, pid = os.pullEvent()
            if ev ~= "window_server_response" then error("Could not find server: " .. ev, 2) end
            server_pid = pid
        end
        kernel.send(server_pid, "window_destroy", win.id)
    end
end