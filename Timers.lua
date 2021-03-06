local addonName, OQ = ...
local oq = OQ:mod() -- thank goodness i stumbled across this trick
local _
if (OQ.table == nil) then
    OQ.table = {}
end
local tbl = OQ.table

OQ.TIMER_RESOLUTION = 100 / 1000 -- 2 times per second

--------------------------------------------------------------------------
-- timer functions
--------------------------------------------------------------------------
function oq.create_timer()
    if (oq.timers == nil) then
        oq.next_timer_cycle = 0
        oq.timer_slice = OQ.TIMER_RESOLUTION -- no more than 10 cycles per second; helps throttle for high framerate machines

        oq.timers = tbl.new()
        oq.ui_timer = CreateFrame('Frame', 'OQ_TimerFrame')
        oq.ui_timer._thread = coroutine.create(oq.timer_coroutine_func)
        oq.ui_timer._counter = 0
        oq.ui_timer._ticker = 0
        oq.ui_timer._restarts = 0
        oq.ui_timer._throttle = 0.5
        oq.ui_timer:SetScript('OnUpdate', oq.timer_coroutine)
        oq.ui_timer:SetScript(
            'OnHide',
            function(self)
                print('timer-hidden')
                self:Show()
            end
        )
        oq.ui_timer:SetSize(2, 2)
        oq.ui_timer:Show()
    end
end

function oq.stop_timer()
    oq.ui_timer._done = true
end

function oq.is_timer(id)
    return ((oq.timers ~= nil) and (oq.timers[id] ~= nil))
end

function oq.timer(id, dt_, func_, repeater, arg1_, arg2_, arg3_, arg4_, arg5_, arg6_, arg7_)
    if (oq.timers == nil) then
        oq.create_timer()
    end

    if (func_ == nil) then
        oq.timers[id] = tbl.delete(oq.timers[id])
    else
        if (oq.timers[id] == nil) then
            oq.timers[id] = tbl.new()
        end
        oq.timers[id].dt = dt_
        oq.timers[id].tm = GetTime() + dt_
        oq.timers[id].one_shot = (not repeater)
        oq.timers[id].func = func_
        oq.timers[id].arg1 = arg1_
        oq.timers[id].arg2 = arg2_
        oq.timers[id].arg3 = arg3_
        oq.timers[id].arg4 = arg4_
        oq.timers[id].arg5 = arg5_
        oq.timers[id].arg6 = arg6_
        oq.timers[id].arg7 = arg7_
    end
end

function oq.timer_coroutine(t, elapsed)
    t._counter = t._counter + elapsed
    if (t._counter >= t._throttle) then
        t._counter = t._counter - t._throttle
        if (coroutine.status(t._thread) == 'dead') then
            -- thread died (how??)... restart
            t._restarts = t._restarts + 1
            t._thread = coroutine.create(oq.timer_coroutine_func)
        elseif (coroutine.status(t._thread) == 'suspended') then
            coroutine.resume(t._thread)
        end
    end
end

function oq.timer_coroutine_func()
    while (oq.ui_timer._done == nil) do
        oq.timer_trigger(GetTime())
        oq.ui_timer._ticker = oq.ui_timer._ticker + 1
        coroutine.yield()
    end
end

function oq.timer_clear()
    tbl.clear(oq.timers, true)
end

function oq.timer_dump(opt)
    local arg = nil
    if (opt) and (opt:find(' ')) then
        arg = strlower(opt:sub(opt:find(' ') + 1, -1))
    end

    print('--[ timers ]------')
    local now = GetTime()
    for i, v in pairs(oq.timers) do
        if (arg) then
            if (v.one_shot) then
                print('  ' .. string.format('%6.3f', v.dt) .. '  ' .. tostring(i) .. '   one_shot')
            else
                print('  ' .. string.format('%6.3f', v.dt) .. '  ' .. tostring(i))
            end
        else
            if (v.one_shot) then
                print('  ' .. oq.render_tm(v.tm - now, true) .. '  ' .. tostring(i) .. '   one_shot')
            else
                print('  ' .. oq.render_tm(v.tm - now, true) .. '  ' .. tostring(i))
            end
        end
    end
    print('--')
end

oq.one_shot = 0
function oq.timer_oneshot(dt_, func_, arg1_, arg2_, arg3_, arg4_, arg5_, arg6_, arg7_)
    oq.one_shot = oq.one_shot + 1
    oq.timer('one_shot.' .. oq.one_shot, dt_, func_, nil, arg1_, arg2_, arg3_, arg4_, arg5_, arg6_, arg7_)
end

-- resets timer to now + dt
function oq.timer_reset(id, dt)
    if (oq.timers[id] ~= nil) then
        local now = GetTime()
        if (dt == nil) then
            dt = oq.timers[id].dt
        end
        oq.timers[id].tm = now + dt
    end
end

function oq.timer_trigger(now)
    if (now < oq.next_timer_cycle) then
        return
    end
    for i, v in pairs(oq.timers) do
        if (v.tm) and (v.tm < now) then
            local arg1 = v.arg1
            if (arg1 == nil) or (arg1 == '#now') then
                arg1 = now
            end
            local retOK, rc
            oq._timer_id = i
            retOK, rc = pcall(v.func, arg1, v.arg2, v.arg3, v.arg4, v.arg5, v.arg6, v.arg7)
            if (retOK == true) then
                if (rc ~= nil) or (v == nil) or (v.one_shot) or (v.dt == nil) or (v.dt == 0) then
                    oq.timers[i] = tbl.delete(oq.timers[i])
                else
                    v.error_cnt = nil
                    v.tm = now + v.dt
                end
            else
                v.error_cnt = (v.error_cnt or 0) + 1
                if ((v.error_cnt % 5) == 0) then
                    print(OQ.LILREDX_ICON .. "  OQ: error calling '" .. tostring(i) .. "'  error: " .. tostring(rc))
                    print(OQ.LILREDX_ICON .. '  OQ: removing timer')
                    oq.timers[i] = tbl.delete(oq.timers[i])
                end
            end
            if ((GetTime() - now) > 0.25) then
                return
            end
        end
    end

    oq.next_timer_cycle = GetTime() + oq.timer_slice
end

function oq.timer_trip(id)
    if (oq.timers[id] ~= nil) then
        oq.timers[id].tm = 0
    end
end
