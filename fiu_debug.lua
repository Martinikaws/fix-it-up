--[[
    Martini Hub debug: finds out why the script misbehaves on an executor, in the live game, and writes a report.

    On any PC, just run:
      loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()

    On SOMEONE ELSE'S PC (the report comes back to your Discord by itself, nothing to click):
      getgenv().FIU_DEBUG_WEBHOOK = "https://discord.com/api/webhooks/..."
      loadstring(game:HttpGet("https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/fiu_debug.lua"))()
    That runs the Quick check and posts the report (as a .txt file) to the webhook: once before loading the main
    script (in case the load crashes the game) and once at the end. Without FIU_DEBUG_WEBHOOK it uses the URL saved in
    the Webhook tab (FixItUp/webhook.json), or the one pasted in this window.

    Quick check (safe: nothing moves, nothing is bought): what the executor has and whether it really works (files,
    HTTP, compiler, confirm dialogs, clicks), compiles the main script and the Obsidian UI library with this
    executor's compiler, reads the script's own logs, then loads the real script and catches the exact error.
    Full test adds the old game tests: paths, a store click (always declined), spawning one of your cars, five ways of
    sitting in it, a short drive, the hood, and one part removed and put back.

    Written without newer Luau syntax (no +=, //, generalized for, if-expressions), so it still runs on an executor
    whose compiler can't build the main script.
]]

local Players, RS, RunService = game:GetService("Players"), game:GetService("ReplicatedStorage"), game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LP = Players.LocalPlayer
local DIR = "FixItUp"
local RAW = "https://raw.githubusercontent.com/Martinikaws/fix-it-up/main/"
local OBSIDIAN = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local D = { lines = {}, t0 = os.clock(), busy = false, pass = 0, fail = 0, warn = 0, exec = "?", fails = {} }
local genv = (getgenv and getgenv()) or _G

-- the main script hooks the confirm dialogs and moves you around: it must not run during the tests (the load test
-- starts it again on purpose)
if genv.FIU_MAIN then pcall(genv.FIU_MAIN.unload) end
genv.FIU_TOKEN = {} -- stops a queued hop reload from starting a copy mid-test
task.wait(0.5)

-- ============================== report ==============================
function D.put(tag, msg)
    if tag == "PASS" then D.pass = D.pass + 1 elseif tag == "FAIL" then D.fail = D.fail + 1 elseif tag == "WARN" then D.warn = D.warn + 1 end
    local line = ("[%6.1f] %-4s %s"):format(os.clock() - D.t0, tag, tostring(msg))
    D.lines[#D.lines + 1] = line
    if tag == "FAIL" or tag == "WARN" then D.fails[#D.fails + 1] = line end
    if D.refresh then D.refresh() end
end
local put = D.put
local function chk(cond, name, detail)
    put(cond and "PASS" or "FAIL", name .. (detail and (" - " .. tostring(detail)) or ""))
    return cond
end
function D.text()
    local head = ("Martini Hub debug report | %s | executor %s | place %s | job %s | user %s | %d players\n"):format(os.date("%Y-%m-%d %H:%M:%S"),
        D.exec, tostring(game.PlaceId), game.JobId:sub(1, 8), LP.Name, #Players:GetPlayers())
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

-- ============================== send to Discord ==============================
function D.validUrl(u)
    return type(u) == "string" and (u:match("^https://discord%.com/api/webhooks/%d+/[%w_%-]+")
        or u:match("^https://discordapp%.com/api/webhooks/%d+/[%w_%-]+")
        or u:match("^https://%a+%.discord%.com/api/webhooks/%d+/[%w_%-]+")) ~= nil
end
function D.webhook()
    if D.validUrl(genv.FIU_DEBUG_WEBHOOK) then return genv.FIU_DEBUG_WEBHOOK end
    if D.urlBox and D.validUrl(D.urlBox.Text) then return D.urlBox.Text end
    local ok, raw = pcall(readfile, DIR .. "/webhook.json")
    if ok and type(raw) == "string" then
        local ok2, t = pcall(HttpService.JSONDecode, HttpService, raw)
        if ok2 and type(t) == "table" and D.validUrl(t.url) then return t.url end
    end
    return nil
end
function D.request()
    return (type(request) == "function" and request) or (type(http_request) == "function" and http_request)
        or (syn and type(syn.request) == "function" and syn.request) or (fluxus and type(fluxus.request) == "function" and fluxus.request) or nil
end
-- the whole report as a .txt attachment (multipart), with a summary embed; if the executor's request() can't do
-- multipart, the report goes as several plain messages instead
function D.send(label)
    local url = D.webhook()
    if not url then return false, "no webhook URL (set getgenv().FIU_DEBUG_WEBHOOK, paste one here, or save one in the Webhook tab)" end
    local r = D.request()
    if not r then return false, "this executor has no request() function: use Copy report instead" end
    local text = D.text()
    local fails = table.concat(D.fails, "\n")
    if #fails > 3000 then fails = fails:sub(1, 3000) .. "\n..." end
    local embed = {
        title = ("Debug report%s: %s"):format(label and (" (" .. label .. ")") or "", D.exec),
        description = ("**%d pass · %d fail · %d warn**\n%s"):format(D.pass, D.fail, D.warn,
            fails ~= "" and ("```\n" .. fails:gsub("```", "'''") .. "\n```") or "no failures"),
        color = D.fail > 0 and 0xe0233c or (D.warn > 0 and 0xf59e0b or 0x10b981),
        footer = { text = ("%s · place %s · server %s"):format(LP.Name, tostring(game.PlaceId), game.JobId:sub(1, 8)) },
    }
    local payload = HttpService:JSONEncode({ username = "Martini Hub debug", embeds = { embed } })
    local b = "MartiniHubDebug" .. tostring(math.random(100000, 999999))
    local name = ("debug_%s_%s.txt"):format((D.exec:gsub("[^%w]", "")), LP.Name)
    local body = table.concat({
        "--" .. b, 'Content-Disposition: form-data; name="payload_json"', "Content-Type: application/json", "", payload,
        "--" .. b, ('Content-Disposition: form-data; name="files[0]"; filename="%s"'):format(name), "Content-Type: text/plain", "", text,
        "--" .. b .. "--", "" }, "\r\n")
    local ok, res = pcall(r, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "multipart/form-data; boundary=" .. b }, Body = body })
    local code = ok and type(res) == "table" and (res.StatusCode or res.status or res.Status) or 0
    if tonumber(code) and tonumber(code) >= 200 and tonumber(code) < 300 then return true, "sent as a file" end
    -- fallback: summary + the report in code blocks, 1900 characters each (Discord's limit is 2000), at most 8
    local function post(t)
        local ok2, res2 = pcall(r, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = HttpService:JSONEncode(t) })
        local c = ok2 and type(res2) == "table" and tonumber(res2.StatusCode or res2.status or res2.Status) or 0
        return c >= 200 and c < 300, ok2 and ("HTTP " .. tostring(c)) or tostring(res2)
    end
    local okE, whyE = post({ username = "Martini Hub debug", embeds = { embed } })
    if not okE then return false, ("upload failed (%s), plain post failed too (%s)"):format(ok and ("HTTP " .. tostring(code)) or tostring(res), whyE) end
    local i, n = 1, 0
    while i <= #text and n < 8 do
        task.wait(1.2)
        post({ username = "Martini Hub debug", content = "```\n" .. text:sub(i, i + 1899):gsub("```", "'''") .. "\n```" })
        i, n = i + 1900, n + 1
    end
    return true, i <= #text and "sent as messages (report cut after 8, the full one is in FixItUp/debug_<UserId>.txt)" or "sent as messages"
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

-- a global by name, also "a|b|syn.c" (first one that exists); returns value, the name that matched
local function fn(names)
    for n in names:gmatch("[^|]+") do
        local ok, v = pcall(function()
            local cur = genv
            for part in n:gmatch("[^%.]+") do cur = cur and cur[part] end
            if cur == nil and not n:find("%.") then cur = getfenv and getfenv(0)[n] end
            return cur
        end)
        if ok and v ~= nil then return v, n end
    end
    return nil
end

-- what the executor has, and whether it really works (an executor can define a function that does nothing or throws)
function T.exec()
    local ex, ver = "?", ""
    for _, n in ipairs({ "identifyexecutor", "getexecutorname" }) do
        local f = fn(n)
        if type(f) == "function" then local ok, a, b = pcall(f); if ok and a then ex, ver = tostring(a), tostring(b or "") break end end
    end
    D.exec = (ex .. " " .. ver):gsub("%s+$", "")
    put("INFO", ("executor: %s · %s"):format(D.exec, tostring(_VERSION)))
    -- every executor function the main script calls, what for, and what it does without it
    local NEED = {
        { "getgenv", "shared state between copies of the script", "BREAKS: the script can't start" },
        { "loadstring", "loading the Obsidian UI library and the reload after a hop", "BREAKS: no menu" },
        { "readfile", "every saved setting", "BREAKS" }, { "writefile", "every saved setting", "BREAKS" },
        { "isfile", "settings", "BREAKS" }, { "isfolder", "settings folder", "BREAKS" }, { "makefolder", "settings folder", "BREAKS" },
        { "appendfile", "errors.txt and life.log", "logs are lost" }, { "listfiles", "multi-account grouping, configs list", "configs list empty" },
        { "request|http_request|syn.request|fluxus.request", "webhook, server list for hops, staff list", "no webhook, no hops" },
        { "queue_on_teleport|queueonteleport|syn.queue_on_teleport", "reloading the script after a hop / rejoin", "no reload after hops" },
        { "fireclickdetector", "store, hood, machines, junk cars", "real mouse clicks instead (slower)" },
        { "fireproximityprompt", "sell, wash, paint prompts", "InputHoldBegin fallback (needs to be in range)" },
        { "getcallbackvalue", "reading the game's confirm dialogs", "getrenv()._G, else a Yes/No box you must click" },
        { "getrenv", "fallback for the confirm dialogs", "Yes/No box if getcallbackvalue is missing too" },
        { "getcustomasset", "the logo", "a wrench icon" }, { "gethui", "where the menu lives", "CoreGui" },
        { "setclipboard", "copy buttons", "copy buttons do nothing" }, { "identifyexecutor|getexecutorname", "picking the click route", "-" },
    }
    local miss = {}
    for _, n in ipairs(NEED) do
        local v, got = fn(n[1])
        if v == nil then
            miss[#miss + 1] = n[1]
            put(n[3]:find("^BREAKS") and "FAIL" or "WARN", ("missing %s (%s): %s"):format(n[1], n[2], n[3]))
        else
            put("INFO", ("has %s (%s)"):format(got, type(v)))
        end
    end
    put(#miss == 0 and "PASS" or "INFO", ("%d of %d functions present"):format(#NEED - #miss, #NEED))
    -- getgenv really shared
    chk(pcall(function() genv.__fiu_dbg = 42; assert(getgenv().__fiu_dbg == 42) end), "getgenv() keeps values")
    -- files: the settings bug ("changing a setting breaks the script until menukey.json is deleted") lived here, so
    -- test overwriting an existing file, nested folders (SaveManager), appending and listing
    chk(pcall(function() if not isfolder(DIR) then makefolder(DIR) end; assert(isfolder(DIR)) end), "makefolder / isfolder FixItUp")
    local f1 = DIR .. "/_dbg.txt"
    chk(pcall(function() writefile(f1, "first"); assert(readfile(f1) == "first") end), "writefile + readfile")
    local okO, errO = pcall(function() writefile(f1, "second, longer"); local r = readfile(f1); assert(r == "second, longer", "read back: " .. tostring(r)) end)
    chk(okO, "overwrite an existing file", not okO and errO or nil)
    local okA, errA = pcall(function() appendfile(f1, "+"); assert(readfile(f1) == "second, longer+", "read back: " .. tostring(readfile(f1))) end)
    chk(okA, "appendfile", not okA and errA or nil)
    local okN, errN = pcall(function()
        if not isfolder(DIR .. "/_dbg") then makefolder(DIR .. "/_dbg") end
        writefile(DIR .. "/_dbg/x.json", HttpService:JSONEncode({ a = 1, b = "two" }))
        local t = HttpService:JSONDecode(readfile(DIR .. "/_dbg/x.json"))
        assert(t.a == 1 and t.b == "two")
    end)
    chk(okN, "nested folder + JSON round trip (what configs do)", not okN and errN or nil)
    local okL, list = pcall(listfiles, DIR)
    if okL and type(list) == "table" then
        put("PASS", ("listfiles: %d entries, e.g. %s"):format(#list, tostring(list[1])))
    else
        put("WARN", "listfiles failed: " .. tostring(list))
    end
    pcall(function() delfile(DIR .. "/_dbg/x.json") end)
    -- menukey.json: a value Enum.KeyCode doesn't have used to kill the script at load
    local okM, raw = pcall(readfile, DIR .. "/menukey.json")
    if okM and type(raw) == "string" then
        put("INFO", "menukey.json: " .. raw:sub(1, 200))
        local okJ, t = pcall(HttpService.JSONDecode, HttpService, raw)
        if not okJ or type(t) ~= "table" then put("FAIL", "menukey.json isn't valid JSON: " .. tostring(t))
        else
            for k, v in pairs(t) do
                local good = v == "None" or v == "MB1" or v == "MB2" or v == "MB3" or (type(v) == "string" and pcall(function() return Enum.KeyCode[v] end))
                put(good and "PASS" or "WARN", ("menukey.json %s = %s %s"):format(tostring(k), tostring(v), good and "ok" or "(not a key: ignored by the script)"))
            end
        end
    else
        put("INFO", "menukey.json: none")
    end
    -- HTTP
    local t0 = os.clock()
    local okH, body = pcall(function() return game:HttpGet(RAW .. "README.md") end)
    chk(okH and type(body) == "string" and #body > 20, "game:HttpGet", okH and ("%d bytes in %.1fs"):format(type(body) == "string" and #body or 0, os.clock() - t0) or tostring(body))
    local r = D.request()
    if r then
        local okR, res = pcall(r, { Url = RAW .. "README.md", Method = "GET" })
        if okR and type(res) == "table" then
            local keys = {}
            for k in pairs(res) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            chk(res.StatusCode == 200 and type(res.Body) == "string", "request() GET",
                ("StatusCode=%s, Body %s, fields: %s"):format(tostring(res.StatusCode), type(res.Body), table.concat(keys, ",")))
        else
            put("FAIL", "request() GET threw: " .. tostring(res))
        end
    end
    -- compiler: each newer Luau feature on its own, so a failure names the one this executor lacks
    if type(loadstring) == "function" then
        for _, c in ipairs({
            { "basic", "return 1 + 1", 2 },
            { "compound assignment (+=)", "local x = 1; x += 2; return x", 3 },
            { "floor division (//)", "return 7 // 2", 3 },
            { "if-expression", "local a = 5; return if a > 2 then 1 else 0", 1 },
            { "generalized for (for k, v in t do)", "local s = 0; for _, v in {1, 2, 3} do s += v end; return s", 6 },
            { "type annotations", "local function f(x: number): number return x * 2 end; return f(2)", 4 },
            { "continue", "local s = 0; for i = 1, 4 do if i == 2 then continue end; s += i end; return s", 8 },
            { "string interpolation", "local n = 3; return `n{n}`", "n3" },
        }) do
            local okC, f, cerr = pcall(loadstring, c[2])
            local okR, v = false, nil
            if okC and type(f) == "function" then okR, v = pcall(f) end
            local detail
            if not (okC and type(f) == "function") then detail = "won't compile: " .. tostring(okC and cerr or f)
            elseif not okR then detail = "errors when run: " .. tostring(v)
            elseif v ~= c[3] then detail = "wrong result: " .. tostring(v) end
            chk(okR and v == c[3], "compiler: " .. c[1], detail)
        end
    end
    -- the confirm dialogs: which route the main script will use
    local conf = RS:FindFirstChild("Events") and RS.Events:FindFirstChild("HUD") and RS.Events.HUD:FindFirstChild("Confirmation")
    local gcv = fn("getcallbackvalue")
    local okG, cur = false, nil
    if conf and type(gcv) == "function" then okG, cur = pcall(gcv, conf, "OnClientInvoke") end
    local okRG, g = pcall(function() return getrenv()._G end)
    local viaG = okRG and type(g) == "table" and g.Confirmation ~= nil
    if okG and type(cur) == "function" then put("PASS", "confirm dialogs: getcallbackvalue reads the game's callback")
    elseif viaG then put("PASS", "confirm dialogs: read from the game's _G (getrenv)")
    elseif type(gcv) == "function" then put("WARN", "confirm dialogs: getcallbackvalue exists but returned " .. tostring(cur) .. " (the HUD may not be built yet)")
    else put("FAIL", "confirm dialogs: no getcallbackvalue and no getrenv()._G: the script shows its own Yes/No box for every buy/sell, so auto flip waits for clicks") end
    -- clicks: the route HOOK.click takes
    local exl = D.exec:lower()
    local real = genv.FIU_REALCLICKS ~= nil or type(fn("fireclickdetector")) ~= "function" or exl:find("xeno") ~= nil or exl:find("solara") ~= nil
    put("INFO", "click route the script will use: " .. (real and "real mouse clicks (camera aim + VirtualInputManager)" or "fireclickdetector"))
    chk(pcall(function() local v = game:GetService("VirtualInputManager"); v:SendMouseMoveEvent(1, 1, game) end), "VirtualInputManager usable")
    chk(pcall(function() game:GetService("VirtualUser") end), "VirtualUser usable")
    -- UI container, custom assets, rendering, threads
    local okU, errU = pcall(function()
        local h = gethui and gethui() or game:GetService("CoreGui")
        local sg = Instance.new("ScreenGui"); sg.Name = "FIU_DbgProbe"; sg.Parent = h; sg:Destroy()
    end)
    chk(okU, "a ScreenGui can be parented to gethui()/CoreGui", not okU and errU or nil)
    local okI, errI = pcall(function()
        local f = "MartiniHub/logo_v1.png"
        if not isfolder("MartiniHub") then makefolder("MartiniHub") end
        if not isfile(f) then writefile(f, game:HttpGet(RAW .. "assets/logo.png")) end
        local id = getcustomasset(f)
        assert(type(id) == "string" and id ~= "", "returned " .. tostring(id))
        return id
    end)
    put(okI and "PASS" or "WARN", "getcustomasset (logo)" .. (okI and "" or (": " .. tostring(errI) .. " (a wrench icon is shown instead)")))
    chk(pcall(RunService.Set3dRenderingEnabled, RunService, true), "Set3dRenderingEnabled (Disable 3D rendering, stats screen)")
    chk(type(task.cancel) == "function", "task.cancel (stuck watchdog)")
    chk(type(debug) == "table" and type(debug.traceback) == "function", "debug.traceback")
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

-- the main script and the Obsidian UI library, compiled by THIS executor's compiler: a compile error here is why
-- nothing shows up (the 200-local limit, or syntax this compiler doesn't know)
function T.compile()
    if type(loadstring) ~= "function" then put("FAIL", "no loadstring: nothing can be compiled") return end
    local function grab(url)
        local t0 = os.clock()
        local ok, src = pcall(function() return game:HttpGet(url) end)
        if not ok or type(src) ~= "string" or #src < 100 then return nil, "download failed: " .. tostring(src) end
        return src, ("%d KB in %.1fs"):format(math.floor(#src / 1024), os.clock() - t0)
    end
    -- the commit on GitHub right now, so the report says which version was tested
    local r = D.request()
    if r then
        pcall(function()
            local res = r({ Url = "https://api.github.com/repos/Martinikaws/fix-it-up/commits/main", Method = "GET", Headers = { ["User-Agent"] = "fiu-debug" } })
            local t = HttpService:JSONDecode(res.Body)
            put("INFO", ("GitHub main is at %s: %s"):format(tostring(t.sha):sub(1, 7), tostring(t.commit and t.commit.message or ""):match("^[^\n]*")))
        end)
    end
    for _, s in ipairs({
        { "main script (fiu_main.lua)", RAW .. "fiu_main.lua", "=fiu_main" },
        { "Obsidian Library.lua", OBSIDIAN .. "Library.lua", "=Obsidian" },
        { "Obsidian ThemeManager.lua", OBSIDIAN .. "addons/ThemeManager.lua", "=ThemeManager" },
        { "Obsidian SaveManager.lua", OBSIDIAN .. "addons/SaveManager.lua", "=SaveManager" },
    }) do
        local src, info = grab(s[2])
        if not src then put("FAIL", s[1] .. ": " .. info)
        else
            local t0 = os.clock()
            local ok, f, err = pcall(loadstring, src, s[3])
            if ok and type(f) == "function" then
                put("PASS", ("%s compiles (%s, compiled in %.2fs)"):format(s[1], info, os.clock() - t0))
                if s[3] == "=fiu_main" then D.mainFn, D.mainSrc = f, src end
            else
                put("FAIL", ("%s does NOT compile on this executor: %s"):format(s[1], tostring(ok and err or f)))
            end
        end
    end
    -- local copies the script prefers over the downloads
    local okL, lib = pcall(isfile, "BattleBotFarm/lib/Library.lua")
    if okL and lib then put("WARN", "BattleBotFarm/lib/Library.lua exists: the script loads that old Obsidian copy instead of downloading it. Delete the BattleBotFarm/lib folder if the menu looks broken.") end
    local okF, loc = pcall(readfile, "fiu_main.lua")
    if okF and type(loc) == "string" then
        local same = D.mainSrc ~= nil and loc == D.mainSrc
        put(same and "INFO" or "WARN", ("local fiu_main.lua (%d KB) %s"):format(math.floor(#loc / 1024),
            same and "matches GitHub" or "differs from GitHub: the hop reload uses it when the download fails"))
    end
end

-- the script's own logs on this PC: errors it caught, the reload after a hop, the load/unload trail
function T.logs()
    local function tail(p, n)
        local ok, s = pcall(readfile, p)
        if not ok or type(s) ~= "string" or s == "" then put("INFO", p .. ": none") return end
        local lines = {}
        for l in s:gmatch("[^\n]+") do lines[#lines + 1] = l end
        put("INFO", ("%s: %d lines, the last %d:"):format(p, #lines, math.min(n, #lines)))
        for i = math.max(1, #lines - n + 1), #lines do put("INFO", "  " .. lines[i]:sub(1, 300)) end
    end
    tail(DIR .. "/errors.txt", 25)
    tail(DIR .. "/reload_error.txt", 5)
    tail(DIR .. "/life.log", 25)
    local okL, list = pcall(listfiles, DIR)
    if okL and type(list) == "table" then
        local names = {}
        for _, p in ipairs(list) do names[#names + 1] = tostring(p):match("[^/\\]+$") or tostring(p) end
        table.sort(names)
        put("INFO", "files in FixItUp/: " .. table.concat(names, ", "))
    end
end

-- run the real script and catch what kills it: the error with its line number (chunk "fiu_main"), console errors
-- and warnings while it starts, and new lines in errors.txt. When it works it stays running afterwards.
function T.load()
    if not D.mainFn then T.compile() end
    if not D.mainFn then put("FAIL", "the main script didn't compile here, so it can't be loaded (see above)") return end
    local console, seen = {}, {}
    local conn = game:GetService("LogService").MessageOut:Connect(function(msg, kind)
        if kind ~= Enum.MessageType.MessageError and kind ~= Enum.MessageType.MessageWarning then return end
        local line = (kind == Enum.MessageType.MessageError and "error " or "warn ") .. tostring(msg):sub(1, 400)
        if not seen[line] and #console < 40 then seen[line] = true; console[#console + 1] = line end
    end)
    local okE, errBefore = pcall(readfile, DIR .. "/errors.txt")
    local before = (okE and type(errBefore) == "string") and #errBefore or 0
    local done, ok, err = false, nil, nil
    local t0 = os.clock()
    put("INFO", "loading the main script (up to 60 s)...")
    task.spawn(function()
        ok, err = xpcall(D.mainFn, debug.traceback)
        done = true
    end)
    repeat task.wait(0.25) until done or os.clock() - t0 > 60
    if not done then put("FAIL", "the main script was still starting after 60 s: stuck waiting on something (console lines below)")
    elseif ok then put("PASS", ("main script finished starting in %.1fs"):format(os.clock() - t0))
    else put("FAIL", "main script crashed while starting: " .. tostring(err)) end
    task.wait(8) -- some errors only show once its loops run
    conn:Disconnect()
    local m = genv.FIU_MAIN
    chk(type(m) == "table", "script registered itself (getgenv().FIU_MAIN)")
    if type(m) == "table" and type(m.lib) == "function" then
        local okLib, lib = pcall(m.lib)
        chk(okLib and lib ~= nil, "menu library is up", okLib and lib ~= nil and ("Unloaded=%s"):format(tostring(lib.Unloaded)) or tostring(lib))
    end
    for _, l in ipairs(console) do put("INFO", "console " .. l) end
    if #console == 0 then put("INFO", "console: no errors or warnings while it started") end
    local okA, after = pcall(readfile, DIR .. "/errors.txt")
    if okA and type(after) == "string" and #after > before then
        for l in after:sub(before + 1):gmatch("[^\n]+") do put("FAIL", "errors.txt: " .. l:sub(1, 300)) end
    end
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
                    nSt = nSt + 1
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
        -- back to a clean Running state: the previous attempt can leave Seated on with no seat, and then nothing sits
        h = hum()
        if h then h:ChangeState(Enum.HumanoidStateType.Running) end
        task.wait(0.8)
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
        -- the repair holds a removed part above the car until it's reinstalled (a loose one is left behind); do the same
        local park = car:GetPivot() * CFrame.new(0, 6, 0)
        local pin = RunService.Heartbeat:Connect(function()
            if part.Parent then
                part:PivotTo(park)
                part:SetAttribute("DroppedAt", nil)
                for _, b in ipairs(part:GetDescendants()) do if b:IsA("BasePart") then b.AssemblyLinearVelocity = Vector3.zero; b.AssemblyAngularVelocity = Vector3.zero end end
            end
        end)
        task.wait(0.8)
        car.PartsEvent:FireServer("ReapplyPart", part)
        t0 = os.clock()
        repeat task.wait(0.1) until slot.Value == name or os.clock() - t0 > 6
        chk(slot.Value == name, "ReapplyPart " .. slot.Name, slot.Value == name and ("back in %.1fs"):format(os.clock() - t0) or "NOT reinstalled: " .. part.Name .. " is lying next to the car, put it back by hand")
        pin:Disconnect()
    end
    if D.start then tp(D.start) end
end

-- ============================== UI ==============================
local QUICK = { "exec", "compile", "logs", "load" } -- safe: nothing moves, nothing is bought
local FULL = { "exec", "compile", "logs", "paths", "store", "spawn", "parts", "load" }

-- runs tests in order; send = post the report to the webhook (once before the load test, which can crash the game,
-- and once at the end)
local function run(names, send)
    if D.busy then put("WARN", "already running") return end
    D.busy = true
    task.spawn(function()
        for _, n in ipairs(names) do
            if n == "load" and send and D.webhook() then
                local ok, why = D.send("before loading the script")
                put(ok and "INFO" or "WARN", "webhook (before the load test): " .. tostring(why))
            end
            put("INFO", "=== " .. n .. " ===")
            local ok, err = xpcall(T[n], debug.traceback)
            if not ok then put("FAIL", n .. " crashed: " .. tostring(err)) end
            D.save()
        end
        pcall(function() local h = hum(); if h then h:SetStateEnabled(Enum.HumanoidStateType.Seated, true) end end)
        put("INFO", ("done: %d pass, %d fail, %d warn. Saved to %s/debug_%d.txt%s"):format(D.pass, D.fail, D.warn, DIR, LP.UserId,
            D.copy() and ", copied to the clipboard" or ""))
        D.save()
        if send then
            local ok, why = D.send("final")
            put(ok and "PASS" or "WARN", "webhook: " .. tostring(why))
        end
        D.busy = false
    end)
end

local function buildUI()
    local parent = (gethui and gethui()) or game:GetService("CoreGui")
    pcall(function() local old = parent:FindFirstChild("FIU_Debug"); if old then old:Destroy() end end)
    local gui = Instance.new("ScreenGui")
    gui.Name, gui.ResetOnSpawn, gui.DisplayOrder = "FIU_Debug", false, 2000
    if not pcall(function() gui.Parent = parent end) then gui.Parent = LP:WaitForChild("PlayerGui") end
    D.gui = gui
    local f = Instance.new("Frame")
    f.Size, f.Position, f.BackgroundColor3, f.BorderSizePixel, f.Active, f.Draggable = UDim2.fromOffset(600, 470), UDim2.new(0, 10, 0.5, -235), Color3.fromRGB(18, 23, 20), 0, true, true
    f.Parent = gui
    -- small screens (phones, tiny windows): shrink the whole window to fit
    pcall(function()
        local vp = workspace.CurrentCamera.ViewportSize
        local s = math.min(1, (vp.X - 20) / 600, (vp.Y - 20) / 470)
        if s < 1 then local sc = Instance.new("UIScale"); sc.Scale = s; sc.Parent = f; f.Position = UDim2.fromOffset(10, 10) end
    end)
    local title = Instance.new("TextLabel")
    title.Size, title.Position, title.BackgroundTransparency, title.TextXAlignment = UDim2.new(1, -10, 0, 22), UDim2.fromOffset(8, 4), 1, Enum.TextXAlignment.Left
    title.Text, title.TextColor3, title.Font, title.TextSize, title.Parent = "Martini Hub debug", Color3.fromRGB(16, 185, 129), Enum.Font.GothamBold, 15, f
    local function mk(text, x, y, w, cb, accent)
        local b = Instance.new("TextButton")
        b.Size, b.Position, b.TextColor3, b.Font, b.TextSize, b.BorderSizePixel = UDim2.fromOffset(w, 26), UDim2.fromOffset(x, y), Color3.new(1, 1, 1), Enum.Font.Gotham, 13, 0
        b.BackgroundColor3 = accent and Color3.fromRGB(16, 140, 100) or Color3.fromRGB(29, 42, 35)
        b.Text, b.Parent = text, f
        b.MouseButton1Click:Connect(cb)
        return b
    end
    -- row 1: the two main runs
    mk("Quick check (safe)", 8, 30, 150, function() run(QUICK, D.webhook() ~= nil) end, true)
    mk("Full test (spawns a car)", 164, 30, 170, function() run(FULL, D.webhook() ~= nil) end)
    mk("Executor only", 340, 30, 110, function() run({ "exec", "compile" }, false) end)
    mk("Load script", 456, 30, 136, function() run({ "load" }, false) end)
    -- row 2: single game tests + report
    mk("Store click", 8, 60, 90, function() run({ "store" }, false) end)
    mk("Spawn + seat", 104, 60, 100, function() run({ "spawn" }, false) end)
    mk("Hood + parts", 210, 60, 100, function() run({ "parts" }, false) end)
    mk("Copy report", 316, 60, 100, function() D.save(); put("INFO", D.copy() and "report copied" or "setclipboard not available: the report is in FixItUp/debug_" .. LP.UserId .. ".txt") end)
    mk("Close", 422, 60, 70, function() gui:Destroy() end)
    -- row 3: webhook
    local box = Instance.new("TextBox")
    box.Size, box.Position, box.BackgroundColor3, box.BorderSizePixel = UDim2.fromOffset(440, 26), UDim2.fromOffset(8, 90), Color3.fromRGB(10, 13, 11), 0
    box.ClearTextOnFocus, box.Font, box.TextSize, box.TextColor3, box.PlaceholderColor3 = false, Enum.Font.Code, 12, Color3.fromRGB(232, 242, 236), Color3.fromRGB(120, 130, 125)
    box.TextXAlignment, box.TextTruncate, box.Text = Enum.TextXAlignment.Left, Enum.TextTruncate.AtEnd, ""
    box.PlaceholderText = D.webhook() and "webhook found (Webhook tab or FIU_DEBUG_WEBHOOK)" or "paste a Discord webhook URL to send the report there"
    box.Parent = f
    D.urlBox = box
    mk("Send to Discord", 454, 90, 138, function()
        task.spawn(function()
            D.save()
            local ok, why = D.send("manual")
            put(ok and "PASS" or "WARN", "webhook: " .. tostring(why))
        end)
    end, true)
    local scroll = Instance.new("ScrollingFrame")
    scroll.Size, scroll.Position, scroll.BackgroundColor3, scroll.BorderSizePixel = UDim2.new(1, -16, 1, -152), UDim2.fromOffset(8, 122), Color3.fromRGB(10, 13, 11), 0
    scroll.AutomaticCanvasSize, scroll.CanvasSize, scroll.ScrollBarThickness, scroll.Parent = Enum.AutomaticSize.Y, UDim2.new(), 6, f
    local label = Instance.new("TextLabel")
    label.Size, label.AutomaticSize, label.BackgroundTransparency, label.TextXAlignment, label.TextYAlignment = UDim2.new(1, -8, 0, 0), Enum.AutomaticSize.Y, 1, Enum.TextXAlignment.Left, Enum.TextYAlignment.Top
    label.TextWrapped, label.Font, label.TextSize, label.TextColor3, label.Text, label.Parent = true, Enum.Font.Code, 12, Color3.fromRGB(232, 242, 236), "", scroll
    function D.refresh()
        local from = math.max(1, #D.lines - 350)
        label.Text = table.concat(D.lines, "\n", from)
        task.defer(function() scroll.CanvasPosition = Vector2.new(0, 1e6) end)
    end
    local note = Instance.new("TextLabel")
    note.Size, note.Position, note.BackgroundTransparency, note.TextXAlignment, note.TextWrapped = UDim2.new(1, -16, 0, 24), UDim2.new(0, 8, 1, -28), 1, Enum.TextXAlignment.Left, true
    note.Text = "Quick check never moves you or spends anything; it ends by loading the real script, which stays running if it works."
    note.TextColor3, note.Font, note.TextSize, note.Parent = Color3.fromRGB(180, 190, 185), Enum.Font.Gotham, 11, f
end

buildUI()
D.refresh()
if D.validUrl(genv.FIU_DEBUG_WEBHOOK) then
    put("INFO", "FIU_DEBUG_WEBHOOK set: running the Quick check and sending the report to Discord by itself.")
    run(QUICK, true)
else
    put("INFO", "ready. Quick check (about 30 s) is safe: it tests the executor, compiles and loads the script. Full test also spawns one of your cars.")
end
