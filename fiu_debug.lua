--[[
    CruelHub debug: tests the pieces the Fix It Up! script depends on, in the live game, and writes a report.
    Run it ALONE on the account (it unloads the main script first), standing on open flat ground outside any
    building, with at least one car in your garage:

      loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()

    Buttons: Run all / Env + paths / Store click / Spawn + seat / Hood + parts / Copy report / Close.
    Report: copied to the clipboard, saved to FixItUp/debug_<UserId>.txt, shown in the window.
    Nothing is bought or sold. The seat test spawns one of your garage cars next to you; the parts test takes one
    part off that car and puts it back.
]]

local Players, RS, RunService = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("RunService")
local LP = Players.LocalPlayer
local DIR = "FixItUp"
local D = { lines = {}, t0 = os.clock(), busy = false, pass = 0, fail = 0, warn = 0 }

-- the main script hooks the confirm dialogs and moves you around: it must not run during the tests
if getgenv and getgenv().FIU_MAIN then pcall(getgenv().FIU_MAIN.unload) end
if getgenv then getgenv().FIU_TOKEN = {} end -- stops a queued hop reload from starting a copy mid-test
task.wait(0.5)

-- ============================== report ==============================
function D.put(tag, msg)
    if tag == "PASS" then D.pass += 1 elseif tag == "FAIL" then D.fail += 1 elseif tag == "WARN" then D.warn += 1 end
    D.lines[#D.lines + 1] = ("[%6.1f] %-4s %s"):format(os.clock() - D.t0, tag, tostring(msg))
    if D.refresh then D.refresh() end
end
local put = D.put
local function chk(cond, name, detail)
    put(cond and "PASS" or "FAIL", name .. (detail and (" - " .. tostring(detail)) or ""))
    return cond
end
function D.text()
    local head = ("CruelHub debug report | %s | place %s | job %s | user %s | %d players\n"):format(os.date("%Y-%m-%d %H:%M:%S"),
        tostring(game.PlaceId), game.JobId:sub(1, 8), LP.Name, #Players:GetPlayers())
    return head .. table.concat(D.lines, "\n") .. ("\n-- %d pass, %d fail, %d warn --"):format(D.pass, D.fail, D.warn)
end
function D.save()
    pcall(function() if not isfolder(DIR) then makefolder(DIR) end end)
    pcall(writefile, ("%s/debug_%d.txt"):format(DIR, LP.UserId), D.text())
end
function D.copy()
    local ok = pcall(function() setclipboard(D.text()) end)
    return ok
end

-- ============================== helpers ==============================
local function char() return LP.Character end
local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function stream(pos, t)
    local done = false
    task.spawn(function() pcall(function() LP:RequestStreamAroundAsync(pos, t) end); done = true end)
    local s = os.clock()
    repeat task.wait() until done or os.clock() - s > t + 1
    return done
end
local function exitSeat()
    local h = hum()
    if h and h.SeatPart then
        local t = os.clock()
        repeat h.Sit = false; h:ChangeState(Enum.HumanoidStateType.Jumping); task.wait(0.1) until not h.SeatPart or os.clock() - t > 2
        task.wait(0.15)
    end
end
local function tp(cf)
    exitSeat()
    local r = hrp()
    if not r then return false end
    if typeof(cf) == "Vector3" then cf = CFrame.new(cf) end
    if (cf.Position - r.Position).Magnitude > 64 then stream(cf.Position, 3) end
    r.AssemblyLinearVelocity, r.AssemblyAngularVelocity = Vector3.zero, Vector3.zero
    char():PivotTo(cf)
    return true
end
local function ground(pos)
    local p = RaycastParams.new()
    p.FilterType = Enum.RaycastFilterType.Exclude
    p.FilterDescendantsInstances = { char(), workspace:FindFirstChild("Vehicles"), workspace:FindFirstChild("MoveableParts") }
    local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -200, 0), p)
    return hit and hit.Position
end
local function path(p)
    local cur = game
    for part in p:gmatch("[^%.]+") do cur = cur and cur:FindFirstChild(part) end
    return cur
end
local function snapshot()
    local t = {}
    local st = path("Players." .. LP.Name .. ".PlayerData.Status")
    for _, v in ipairs(st and st:GetChildren() or {}) do if v:IsA("ValueBase") then t[v.Name] = tostring(v.Value) end end
    return t
end
local function dump(inst, depth, indent, maxN)
    local kids = inst:GetChildren()
    for i, c in ipairs(kids) do
        if i > maxN then put("INFO", indent .. ("... %d more"):format(#kids - maxN)) break end
        put("INFO", ("%s%s [%s]%s"):format(indent, c.Name, c.ClassName, c:IsA("ValueBase") and (" = " .. tostring(c.Value)) or ""))
        if depth > 1 then dump(c, depth - 1, indent .. "  ", maxN) end
    end
end
local function attrs(inst, label)
    local out = {}
    for k, v in pairs(inst:GetAttributes()) do out[#out + 1] = k .. "=" .. tostring(v) end
    table.sort(out)
    put("INFO", ("%s attributes: %s"):format(label, #out > 0 and table.concat(out, ", ") or "(none)"))
end
local function garageEntry()
    local g = path("Players." .. LP.Name .. ".PlayerData.Garage")
    local e = g and g:GetChildren()[1]
    return e, e and e:FindFirstChild("Model") and e.Model.Value or "?"
end
local function carOf(e) return workspace.Vehicles:FindFirstChild(e.Name) end

-- aim the camera at a ClickDetector from an angle a raycast proves is clear, then click it for real
local function aimClick(cd, mode)
    local target = cd.Parent
    local pos = target:IsA("BasePart") and target.Position or (target:IsA("Model") and target:GetBoundingBox().Position)
    local cam, root = workspace.CurrentCamera, hrp()
    if not (pos and cam and root) then return false, "no target / camera / character" end
    local side = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
    side = side.Magnitude > 0.1 and side.Unit or Vector3.new(0, 0, 1)
    local eye
    for _, dir in ipairs({ side + Vector3.new(0, 0.6, 0), Vector3.new(0, 1, 0), side, side + Vector3.new(0, 1.5, 0),
        -side + Vector3.new(0, 0.6, 0), side:Cross(Vector3.yAxis) + Vector3.new(0, 0.6, 0), -side:Cross(Vector3.yAxis) + Vector3.new(0, 0.6, 0) }) do
        local from = pos + dir.Unit * 3
        local hit = workspace:Raycast(from, (pos - from) * 1.3)
        if hit and (hit.Instance == target or hit.Instance:IsDescendantOf(target)) then eye = from break end
    end
    if not eye then return false, "no clear line to the detector" end
    local old = cam.CameraType
    cam.CameraType = Enum.CameraType.Scriptable
    cam.CFrame = CFrame.lookAt(eye, pos)
    if D.gui then D.gui.Enabled = false end
    task.wait()
    local p = cam:WorldToViewportPoint(pos)
    local ok, err = pcall(function()
        if mode == "vim" then
            local vim = game:GetService("VirtualInputManager")
            vim:SendMouseMoveEvent(p.X, p.Y, game); task.wait()
            vim:SendMouseButtonEvent(p.X, p.Y, 0, true, game, 0); task.wait(0.05)
            vim:SendMouseButtonEvent(p.X, p.Y, 0, false, game, 0)
        else
            game:GetService("VirtualUser"):ClickButton1(Vector2.new(p.X, p.Y), cam.CFrame)
        end
    end)
    task.wait(0.05)
    if D.gui then D.gui.Enabled = true end
    cam.CameraType = old
    return ok, err
end
local CLICKS = {
    { "fireclickdetector", function(cd) if not fireclickdetector then return false, "not available" end return pcall(fireclickdetector, cd) end },
    { "real click (VirtualInputManager)", function(cd) return aimClick(cd, "vim") end },
    { "real click (VirtualUser)", function(cd) return aimClick(cd, "vu") end },
}

-- ============================== tests ==============================
local T = {}

function T.env()
    local ex, ver = "?", ""
    if identifyexecutor then local ok, a, b = pcall(identifyexecutor); if ok then ex, ver = tostring(a), tostring(b or "") end end
    put("INFO", ("executor: %s %s"):format(ex, ver))
    local have, miss = {}, {}
    for _, n in ipairs({ "fireclickdetector", "fireproximityprompt", "firetouchinterest", "getcallbackvalue", "getrenv", "hookfunction",
        "queue_on_teleport", "request", "http_request", "readfile", "writefile", "appendfile", "isfile", "isfolder", "makefolder",
        "listfiles", "setclipboard", "gethui", "getconnections", "gethiddenproperty", "sethiddenproperty", "isnetworkowner", "Drawing" }) do
        local ok, v = pcall(function() return getgenv()[n] end)
        if ok and v ~= nil then have[#have + 1] = n else miss[#miss + 1] = n end
    end
    put("INFO", "has: " .. table.concat(have, ", "))
    put(#miss == 0 and "PASS" or "WARN", "missing: " .. (#miss > 0 and table.concat(miss, ", ") or "nothing"))
    chk(pcall(function() local v = game:GetService("VirtualInputManager"); v:SendMouseMoveEvent(1, 1, game) end), "VirtualInputManager usable")
    chk(pcall(function() game:GetService("VirtualUser") end), "VirtualUser usable")
    -- files
    local okW = pcall(function() writefile(DIR .. "/_dbg.txt", "x") end)
    chk(okW and pcall(readfile, DIR .. "/_dbg.txt"), "file read/write in FixItUp/")
    local okM, raw = pcall(readfile, DIR .. "/menukey.json")
    put("INFO", "menukey.json: " .. (okM and raw:sub(1, 200) or "(none)"))
    -- character
    local h, r = hum(), hrp()
    chk(h and r, "character loaded")
    if h then
        put("INFO", ("humanoid: state %s, health %d, walk %d, sit %s, seatpart %s"):format(h:GetState().Name, h.Health, h.WalkSpeed, tostring(h.Sit), tostring(h.SeatPart)))
        local seated = h:GetStateEnabled(Enum.HumanoidStateType.Seated)
        if not chk(seated, "Seated state enabled on your humanoid", not seated and "DISABLED: you sit and pop straight out (the car wash disables it; an error could leave it off)" or nil) then
            h:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
            put("INFO", "re-enabled the Seated state for the next tests")
        end
    end
    put("INFO", ("StreamingEnabled=%s, gravity=%s"):format(tostring(workspace.StreamingEnabled), tostring(workspace.Gravity)))
end

local STATIONS = {
    { "Dealership", Vector3.new(-511, 14, -779), "Dealership" },
    { "Pitstop (large)", Vector3.new(-1048, 25, -389), "Pitstop(Large)" },
    { "Pitstop (small) south", Vector3.new(-557, 15, -1617), "Pitstop(Small)" },
    { "Pitstop (small) west", Vector3.new(-1130, 15, -1546.5), "Pitstop(Small)" },
}
function T.paths()
    local u = "Players." .. LP.Name .. ".PlayerData"
    for _, p in ipairs({ "ReplicatedStorage.Events.Vehicles.RemoteLoad", "ReplicatedStorage.Events.Vehicles.SetDirt", "ReplicatedStorage.Events.Vehicles.SetPaint",
        "ReplicatedStorage.Events.PartsEvent", "ReplicatedStorage.Events.HUD.Confirmation", "ReplicatedStorage.Events.HUD.StoreConfirmation",
        "ReplicatedStorage.Events.HUD.Notifiy", "ReplicatedStorage.Cache.CarList", "ReplicatedStorage.Assets.CarMaterials",
        u .. ".Status", u .. ".Garage", u .. ".Status.KMs", "Workspace.Map.FirstCity.Buildings", "Workspace.Map.CarWashes",
        "Workspace.PartsStore.SpareParts.Parts", "Workspace.Utils.SellCar", "Workspace.Utils.Auctions", "Workspace.Vehicles",
        "Workspace.MoveableParts", "Workspace.Garages" }) do
        local o = path(p)
        chk(o ~= nil, p:gsub("^Players%." .. LP.Name, "Players.<you>"), o and o.ClassName or "MISSING (renamed in an update?)")
    end
    local snap = {}
    for k, v in pairs(snapshot()) do snap[#snap + 1] = k .. "=" .. v end
    table.sort(snap)
    put("INFO", "Status: " .. table.concat(snap, ", "))
    local cl = path("ReplicatedStorage.Cache.CarList")
    put("INFO", "car catalog entries: " .. (cl and #cl:GetChildren() or 0))
    local g = path(u .. ".Garage")
    put("INFO", "garage cars: " .. (g and #g:GetChildren() or 0))
    local e, model = garageEntry()
    if e then
        put("INFO", ("first garage entry: %s (%s) children: %s"):format(e.Name:sub(1, 8), tostring(model), (function()
            local n = {}; for _, c in ipairs(e:GetChildren()) do n[#n + 1] = c.Name end; return table.concat(n, ",") end)()))
    end
    -- repair shops
    local b = path("Workspace.Map.FirstCity.Buildings")
    for _, s in ipairs(STATIONS) do
        local function find()
            for _, x in ipairs(b and b:GetChildren() or {}) do
                if x.Name == s[3] and (x:GetPivot().Position - s[2]).Magnitude < 150 then return s[1] == "Dealership" and x:FindFirstChild("Folder") or x end
            end
        end
        local root = find()
        if not root then stream(s[2], 5); root = find() end
        if not root then put("FAIL", "shop " .. s[1] .. ": building not found")
        else
            local kinds, nSt = {}, 0
            for _, st in ipairs(root:GetChildren()) do
                if st.Name:match("^Station") then
                    nSt += 1
                    for _, m in ipairs(st:GetChildren()) do
                        local ok = m:FindFirstChild("Detector") and m:FindFirstChildWhichIsA("ClickDetector", true)
                        kinds[#kinds + 1] = m.Name .. (ok and "" or "(NO detector/click)")
                    end
                end
            end
            put(nSt > 0 and "PASS" or "FAIL", ("shop %s: %d stations, machines: %s, lift: %s"):format(s[1], nSt, table.concat(kinds, ","),
                tostring(root:FindFirstChild("Lift") ~= nil or root:FindFirstChild("Lifts") ~= nil)))
        end
    end
    -- sell NPC / wash / paint prompts
    local npc = path("Workspace.Utils.SellCar")
    if npc then
        stream(npc:GetPivot().Position, 5)
        local pr = npc:FindFirstChild("Prompt") or npc:WaitForChild("Prompt", 4)
        local pp = pr and pr:FindFirstChildWhichIsA("ProximityPrompt")
        chk(pp ~= nil, "sell NPC prompt", pp and ("enabled=%s range=%s hold=%s"):format(tostring(pp.Enabled), tostring(pp.MaxActivationDistance), tostring(pp.HoldDuration)) or "not streamed in")
    end
end

-- the cheapest store item: a click on it asks for a confirmation we always decline
function T.store()
    local parts = path("Workspace.PartsStore.SpareParts.Parts")
    local best, bestP
    for _, c in ipairs(parts and parts:GetChildren() or {}) do
        for _, m in ipairs(c:GetChildren()) do
            local cd, pr = m:FindFirstChild("ClickDetector"), tonumber(m:GetAttribute("Price"))
            if cd and pr and (not bestP or pr < bestP) then best, bestP = m, pr end
        end
    end
    if not chk(best ~= nil, "store item found") then return end
    put("INFO", ("item: %s/%s price %s, click range %s"):format(best.Parent.Name, best.Name, tostring(bestP), tostring(best.ClickDetector.MaxActivationDistance)))
    local rf = path("ReplicatedStorage.Events.HUD.StoreConfirmation")
    if not rf then put("FAIL", "no StoreConfirmation remote: the store flow changed") return end
    local function current()
        if getcallbackvalue then local ok, f = pcall(getcallbackvalue, rf, "OnClientInvoke"); if ok then return f, true end end
        local ok, g = pcall(function() return getrenv()._G end)
        return ok and g and g.StoreConfirmation or nil, false
    end
    local orig, exact = current()
    put(orig and "PASS" or "WARN", "the game's own store callback " .. (orig and ("read (" .. (exact and "getcallbackvalue" or "_G") .. ")") or "could NOT be read: after this test the store dialog may need a rejoin"))
    local back = hrp() and hrp().CFrame
    local before = snapshot()
    local got
    rf.OnClientInvoke = function(name, price) got = { name = name, price = price, t = os.clock() }; return 0 end
    stream(best:GetPivot().Position, 3)
    tp(CFrame.new(best:GetPivot().Position + Vector3.new(0, 2, 5)))
    task.wait(0.5)
    put("INFO", ("standing %.1f studs from the item"):format((hrp().Position - best:GetPivot().Position).Magnitude))
    for _, m in ipairs(CLICKS) do
        got = nil
        local t0 = os.clock()
        local ok, err = m[2](best.ClickDetector)
        repeat task.wait(0.05) until got or os.clock() - t0 > 2.5
        if got then put("PASS", ("%s: confirmation came after %.2fs (%s for %s)"):format(m[1], got.t - t0, tostring(got.name), tostring(got.price)))
        else put("FAIL", ("%s: no confirmation in 2.5 s%s"):format(m[1], ok == false and (" (" .. tostring(err) .. ")") or "")) end
        task.wait(2.5)
    end
    if orig then rf.OnClientInvoke = orig end
    local after = snapshot()
    local same = true
    for k, v in pairs(before) do if after[k] ~= v then same = false put("INFO", ("status %s changed %s -> %s"):format(k, v, after[k])) end end
    put(same and "PASS" or "WARN", "nothing was charged")
    if back then tp(back) end
end

-- spawn one garage car beside you, then try every way of getting into the DriveSeat and watch what happens
function T.spawn()
    local e, model = garageEntry()
    if not chk(e ~= nil, "a car in the garage") then return end
    local r = hrp()
    local fwd = workspace.CurrentCamera.CFrame.LookVector
    fwd = Vector3.new(fwd.X, 0, fwd.Z).Unit
    local spot = r.Position + fwd * 16
    local gy = ground(spot)
    if not chk(gy ~= nil, "open ground 16 studs ahead", "nothing there: stand on flat open ground and retry") then return end
    D.start = r.CFrame
    local cf = CFrame.lookAt(gy + Vector3.new(0, 4, 0), gy + Vector3.new(0, 4, 0) + fwd)
    put("INFO", ("spawning %s at %s"):format(tostring(model), tostring(cf.Position)))
    stream(cf.Position, 5)
    local t0 = os.clock()
    local ok, res = pcall(function() return RS.Events.Vehicles.RemoteLoad:InvokeServer(e, cf) end)
    put(ok and "PASS" or "FAIL", "RemoteLoad invoke" .. (ok and "" or (": " .. tostring(res))))
    local car
    repeat
        task.wait(0.2)
        car = carOf(e)
        if car and not (car:FindFirstChild("PartsEvent") and car:FindFirstChild("Values") and car.Values:FindFirstChild("Engine") and car:FindFirstChild("DriveSeat")) then car = nil end
    until car or os.clock() - t0 > 20
    if not chk(car ~= nil, "car spawned and ready", car and ("%.1fs"):format(os.clock() - t0) or "no ready car in 20 s") then return end
    task.wait(1.5)
    D.car, D.entry = car, e
    local pv = car:GetPivot().Position
    chk((pv - cf.Position).Magnitude < 25, "car arrived where asked", ("%.1f studs off, Y %.1f vs %.1f"):format((pv - cf.Position).Magnitude, pv.Y, cf.Y))
    attrs(car, "car")
    local kids = {}
    for _, c in ipairs(car:GetChildren()) do kids[#kids + 1] = c.Name end
    put("INFO", "car children: " .. table.concat(kids, ", "))
    put("INFO", "car.Values:"); dump(car.Values, 1, "  ", 40)
    for _, d in ipairs(car:GetDescendants()) do
        if d:IsA("Seat") or d:IsA("VehicleSeat") then
            local occ = d.Occupant
            put("INFO", ("seat %s [%s] disabled=%s occupant=%s anchored=%s size=%s parent=%s"):format(d:GetFullName():gsub("^.-Vehicles%.", ""), d.ClassName,
                tostring(d.Disabled), occ and occ.Parent and occ.Parent.Name or "nil", tostring(d.Anchored), tostring(d.Size), d.Parent.Name))
            attrs(d, "  seat")
        elseif d:IsA("ProximityPrompt") or d:IsA("ClickDetector") then
            if not d:FindFirstAncestor("Hood") then put("INFO", ("%s on %s"):format(d.ClassName, d.Parent:GetFullName():gsub("^.-Vehicles%.", ""))) end
        end
    end
    local seat = car.DriveSeat
    pcall(function() put("INFO", "DriveSeat network owner: " .. tostring(isnetworkowner and isnetworkowner(seat))) end)

    -- every attempt: put yourself away from the car, try, then sample for 3 s
    local h = hum()
    local function attempt(label, prep)
        exitSeat()
        tp(CFrame.new(seat.Position + Vector3.new(0, 3, 9)))
        task.wait(0.6)
        h = hum()
        local ev, conns, t = {}, {}, os.clock()
        local function e2(s) ev[#ev + 1] = ("      %.2f %s"):format(os.clock() - t, s) end
        conns[#conns + 1] = h.StateChanged:Connect(function(o, n) e2(("state %s -> %s"):format(o.Name, n.Name)) end)
        conns[#conns + 1] = h:GetPropertyChangedSignal("SeatPart"):Connect(function() e2("SeatPart = " .. (h.SeatPart and h.SeatPart.Name or "nil")) end)
        conns[#conns + 1] = RS.Events.HUD.Notifiy.OnClientEvent:Connect(function(m) e2("game message: " .. tostring(m)) end)
        t = os.clock()
        local okp, err = pcall(prep)
        local seated, leftAt, firstAt = {}, nil, nil
        for _, at in ipairs({ 0.1, 0.3, 0.6, 1, 1.5, 2, 3 }) do
            repeat task.wait() until os.clock() - t >= at
            local s = h.SeatPart == seat
            seated[#seated + 1] = s and "S" or "-"
            if s and not firstAt then firstAt = at end
            if firstAt and not s and not leftAt then leftAt = at end
        end
        for _, c in ipairs(conns) do c:Disconnect() end
        local kept = seated[#seated] == "S" and not leftAt
        local d = ("%s | seated @0.1/0.3/0.6/1/1.5/2/3s: %s | dist %.1f | state %s%s"):format(label, table.concat(seated, " "),
            (hrp().Position - seat.Position).Magnitude, h:GetState().Name, okp and "" or (" | error: " .. tostring(err)))
        if kept then put("PASS", d) elseif firstAt then put("FAIL", d .. (" | SAT, THEN LEFT after %.1fs"):format(leftAt or 0)) else put("FAIL", d .. " | never sat") end
        for _, l in ipairs(ev) do put("INFO", l) end
        return kept
    end
    local worked
    local function try(label, prep) if attempt(label, prep) and not worked then worked = label end end
    try("A tp above seat + seat:Sit (what the farm does)", function() tp(seat.CFrame * CFrame.new(0, 3, 0)); task.wait(0.3); seat:Sit(h) end)
    try("B tp onto seat, no Sit call (touch only)", function() tp(seat.CFrame * CFrame.new(0, 1.2, 0)) end)
    if firetouchinterest then
        try("C touch event + seat:Sit", function() tp(seat.CFrame * CFrame.new(0, 2, 0)); firetouchinterest(hrp(), seat, 0); task.wait(0.05); firetouchinterest(hrp(), seat, 1); seat:Sit(h) end)
    end
    try("D Humanoid.Sit = true on the seat", function() tp(seat.CFrame * CFrame.new(0, 1.5, 0)); h.Sit = true end)
    try("E seat:Sit + ChangeState(Seated)", function() tp(seat.CFrame * CFrame.new(0, 3, 0)); task.wait(0.2); seat:Sit(h); h:ChangeState(Enum.HumanoidStateType.Seated) end)
    put(worked and "PASS" or "FAIL", "sitting: " .. (worked and ("first method that held = " .. worked) or "NO method kept you in the seat"))
    if not worked then
        put("INFO", "no seat method held: check the game messages above, DriveSeat details, and the car.Values flags (Locked / Owner / Driver)")
        return
    end

    -- the farm's drive loop: move the car by hand with you in it
    exitSeat(); tp(seat.CFrame * CFrame.new(0, 3, 0)); task.wait(0.3); seat:Sit(h); task.wait(1.2)
    if h.SeatPart ~= seat then put("FAIL", "re-seating for the drive test failed") return end
    local km0 = tonumber((snapshot().KMs)) or 0
    local dir = car:GetPivot().LookVector
    dir = Vector3.new(dir.X, 0, dir.Z).Unit
    local start, ejected, t = car:GetPivot().Position, nil, os.clock()
    while os.clock() - t < 3 do
        local dt = RunService.Heartbeat:Wait()
        if h.SeatPart ~= seat then ejected = os.clock() - t break end
        local p = car:GetPivot().Position + dir * 60 * dt
        car:PivotTo(CFrame.lookAt(p, p + dir))
        seat.AssemblyLinearVelocity = dir * 60
    end
    seat.AssemblyLinearVelocity = Vector3.zero
    put(ejected and "FAIL" or "PASS", ("drive loop (60 studs/s, 3 s): moved %.0f studs%s, km %s -> %s"):format((car:GetPivot().Position - start).Magnitude,
        ejected and (", EJECTED after %.1fs"):format(ejected) or ", stayed seated", tostring(km0), tostring(snapshot().KMs)))
    exitSeat()
    if D.start then tp(D.start) end
end

-- hood click, then take one part off the car and put it back (the same PartsEvent calls the repair uses)
function T.parts()
    local car, e = D.car, D.entry
    if not (car and car.Parent) then
        put("INFO", "no car from the seat test: running that first")
        T.spawn()
        car, e = D.car, D.entry
    end
    if not (car and car.Parent) then put("FAIL", "no car to test the hood and parts on") return end
    local det = car:FindFirstChild("Misc") and car.Misc:FindFirstChild("Hood") and car.Misc.Hood:FindFirstChild("Detector")
    local cd = det and det:FindFirstChildWhichIsA("ClickDetector")
    local function hoodOpen() local v = car.Values.Cache:FindFirstChild("IsHoodOpen"); return v ~= nil and v.Value end
    if not cd then put("INFO", "this car has no hood detector (some cars have none)")
    elseif hoodOpen() then put("PASS", "hood already open")
    else
        local out = det.Position - car:GetPivot().Position
        out = Vector3.new(out.X, 0, out.Z)
        out = out.Magnitude > 0.1 and out.Unit or Vector3.new(0, 0, -1)
        local stand = CFrame.lookAt(det.Position + out * 4 + Vector3.new(0, 1, 0), det.Position)
        for _, m in ipairs(CLICKS) do
            tp(stand); task.wait(0.4)
            local t0 = os.clock()
            repeat
                m[2](cd); task.wait(0.5)
            until hoodOpen() or os.clock() - t0 > 11
            if hoodOpen() then put("PASS", ("hood opened with %s after %.1fs"):format(m[1], os.clock() - t0)) break
            else put("FAIL", ("hood did NOT open with %s in 11 s (range %s)"):format(m[1], tostring(cd.MaxActivationDistance))) end
        end
    end
    local eng = car.Values.Engine
    local wears = {}
    for _, v in ipairs(eng:GetChildren()) do
        if v:IsA("StringValue") and v.Value ~= "" and eng.Wear:FindFirstChild(v.Name) then wears[#wears + 1] = v.Name .. "=" .. tostring(eng.Wear[v.Name].Value) end
    end
    put("INFO", "installed parts (wear): " .. table.concat(wears, ", "))
    local slot
    for _, v in ipairs(eng:GetChildren()) do
        if v:IsA("StringValue") and v.Value ~= "" and v.Name ~= "EngineBlock" and eng.Wear:FindFirstChild(v.Name) then slot = v break end
    end
    if not slot then put("INFO", "no removable part found") return end
    local MP = workspace.MoveableParts
    local function mine() local t = {}; for _, p in ipairs(MP:GetChildren()) do if p:GetAttribute("Owner") == LP.Name then t[p] = true end end return t end
    local before, name = mine(), slot.Value
    car.PartsEvent:FireServer("RemovePart", slot.Name)
    local t0, part = os.clock(), nil
    repeat
        task.wait(0.1)
        for p in pairs(mine()) do if not before[p] then part = p end end
    until (part and slot.Value == "") or os.clock() - t0 > 6
    chk(slot.Value == "" and part ~= nil, "RemovePart " .. slot.Name, part and ("part appeared in %.1fs: %s"):format(os.clock() - t0, part.Name) or "slot emptied=" .. tostring(slot.Value == "") .. ", no part appeared")
    if part then
        task.wait(0.5)
        car.PartsEvent:FireServer("ReapplyPart", part)
        t0 = os.clock()
        repeat task.wait(0.1) until slot.Value == name or os.clock() - t0 > 6
        chk(slot.Value == name, "ReapplyPart " .. slot.Name, slot.Value == name and ("back in %.1fs"):format(os.clock() - t0) or "NOT reinstalled: " .. part.Name .. " is lying next to the car, put it back by hand")
    end
    if D.start then tp(D.start) end
end

-- ============================== UI ==============================
local function buildUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    pcall(function() local old = parent:FindFirstChild("FIU_Debug"); if old then old:Destroy() end end)
    local gui = Instance.new("ScreenGui")
    gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "FIU_Debug", false, 2000
    if not pcall(function() gui.Parent = parent end) then gui.Parent = LP:WaitForChild("PlayerGui") end
    D.gui = gui
    local f = Instance.new("Frame")
    f.Size, f.Position, f.BackgroundColor3, f.BorderSizePixel, f.Active, f.Draggable = UDim2.fromOffset(580, 420), UDim2.new(0, 10, 0.5, -210), Color3.fromRGB(22, 22, 28), 0, true, true
    f.Parent = gui
    local title = Instance.new("TextLabel")
    title.Size, title.Position, title.BackgroundTransparency, title.TextXAlignment = UDim2.new(1, -10, 0, 22), UDim2.fromOffset(8, 4), 1, Enum.TextXAlignment.Left
    title.Text, title.TextColor3, title.Font, title.TextSize, title.Parent = "CruelHub debug: stand on open ground, then press Run all", Color3.new(1, 1, 1), Enum.Font.GothamBold, 14, f
    local function mk(text, x, y, w, cb)
        local b = Instance.new("TextButton")
        b.Size, b.Position, b.BackgroundColor3, b.TextColor3, b.Font, b.TextSize, b.BorderSizePixel = UDim2.fromOffset(w, 26), UDim2.fromOffset(x, y), Color3.fromRGB(52, 56, 90), Color3.new(1, 1, 1), Enum.Font.Gotham, 13, 0
        b.Text, b.Parent = text, f
        b.MouseButton1Click:Connect(cb)
        return b
    end
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size, scroll.Position, scroll.BackgroundColor3, scroll.BorderSizePixel = UDim2.new(1, -16, 1, -96), UDim2.fromOffset(8, 88), Color3.fromRGB(14, 14, 18), 0
    scroll.AutomaticCanvasSize, scroll.CanvasSize, scroll.ScrollBarThickness, scroll.Parent = Enum.AutomaticSize.Y, UDim2.new(), 6, f
    local label = Instance.new("TextLabel")
    label.Size, label.AutomaticSize, label.BackgroundTransparency, label.TextXAlignment, label.TextYAlignment = UDim2.new(1, -8, 0, 0), Enum.AutomaticSize.Y, 1, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    label.TextWrapped, label.Font, label.TextSize, label.TextColor3, label.Text, label.Parent = true, Enum.Font.Code, 12, Color3.fromRGB(220, 220, 230), "", scroll
    function D.refresh()
        local from = math.max(1, #D.lines - 350)
        label.Text = table.concat(D.lines, "\n", from)
        task.defer(function() scroll.CanvasPosition = Vector2.new(0, 1e6) end)
    end
    local function run(names)
        if D.busy then put("WARN", "already running") return end
        D.busy = true
        task.spawn(function()
            for _, n in ipairs(names) do
                put("INFO", "=== " .. n .. " ===")
                local ok, err = xpcall(T[n], debug.traceback)
                if not ok then put("FAIL", n .. " crashed: " .. tostring(err)) end
                D.save()
            end
            pcall(function() local h = hum(); if h then h:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end end)
            put("INFO", ("done: %d pass, %d fail, %d warn. Report saved to %s/debug_%d.txt%s"):format(D.pass, D.fail, D.warn, DIR, LP.UserId, D.copy() and " and copied to the clipboard" or " (clipboard not available: use Copy report)"))
            D.save()
            D.busy = false
        end)
    end
    mk("Run all", 8, 30, 90, function() run({ "env", "paths", "store", "spawn", "parts" }) end)
    mk("Env + paths", 104, 30, 110, function() run({ "env", "paths" }) end)
    mk("Store click", 220, 30, 100, function() run({ "store" }) end)
    mk("Spawn + seat", 326, 30, 110, function() run({ "spawn" }) end)
    mk("Hood + parts", 442, 30, 120, function() run({ "parts" }) end)
    mk("Copy report", 8, 60, 120, function() D.save(); put("INFO", D.copy() and "report copied" or "setclipboard not available: the report is in FixItUp/debug_" .. LP.UserId .. ".txt") end)
    mk("Close", 134, 60, 80, function() gui:Destroy() end)
    local note = Instance.new("TextLabel")
    note.Size, note.Position, note.BackgroundTransparency, note.TextXAlignment, note.TextWrapped = UDim2.new(1, -230, 0, 26), UDim2.fromOffset(222, 60), 1, Enum.TextXAlignment.Left, true
    note.Text, note.TextColor3, note.Font, note.TextSize, note.Parent = "The main script is unloaded while this runs; execute it again afterwards.", Color3.fromRGB(180, 180, 190), Enum.Font.Gotham, 11, f
end

buildUI()
put("INFO", "ready. Run all takes about 1-2 minutes: it spawns one of your cars next to you and takes one part off it and puts it back.")
D.refresh()
