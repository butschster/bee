-- Stable local lifetime and physical terminal adapter. The replaceable
-- presenter receives a virtual terminal, never the physical output lease.
local tty = require("tty")
local security = require("security")
local process = require("process")
local channel = require("channel")
local time = require("time")
local uuid = require("uuid")
local model = require("model")
local decode = require("decode")
local decode_input = require("decode_input")
local appearance = require("appearance")
local chrome = require("chrome")

local function new_display(width: integer, height: integer): tty.Viewport
    local view, err = tty.viewport({width = width, height = height})
    if not view then error(tostring(err)) end
    return view
end

local function main(initial_application: string?, secondary_application: string?)
    local input = assert(tty.events())
    local lifecycle = assert(process.events())
    local control = assert(process.listen("bee.workspace.control", {message = true}))
    local commands = assert(process.listen("bee.desktop.command", {message = true}))
    local requests = assert(process.listen("bee.app.request", {message = true}))
    local ready = assert(process.listen("bee.app.ready", {message = true}))
    local replies = assert(process.listen("bee.app.reply", {message = true}))
    local scenes = assert(process.listen("bee.desktop.scene", {message = true}))
    local acknowledgements = assert(process.listen("bee.desktop.ack", {message = true}))
    local settings_requests = assert(process.listen("bee.settings.request", {message = true}))
    assert(tty.start())
    local output = assert(tty.surface({alternate_screen = true, hide_cursor = true, synchronized_output = true}))
    assert(tty.mouse(true))
    local width, height = tty.screen_size()
    -- Present before waiting on any child. No artificial boot delay is added.
    assert(output:present(chrome.boot(width, height), {cursor = {x = 1, y = 1, visible = false}}))
    local owner = tostring(process.pid())
    local session_policy, session_error = security.policy("bee:session_policy")
    if session_error then error(tostring(session_error)) end
    local broker_policy, broker_error = security.policy("bee:broker_policy")
    if broker_error then error(tostring(broker_error)) end
    local presenter_policy, presenter_error = security.policy("bee:presenter_policy")
    if presenter_error then error(tostring(presenter_error)) end
    local session_scope = security.new_scope({session_policy})
    local broker_scope = security.new_scope({broker_policy})
    local presenter_scope = security.new_scope({presenter_policy})
    local session = tostring(assert(process.with_options({}):with_scope(session_scope)
        :spawn_monitored("bee.session:main", "bee:workers", owner, width, height)))
    local broker = tostring(assert(process.with_options({}):with_scope(broker_scope)
        :spawn_monitored("bee.applications:broker", "bee:workers", owner)))
    local scene = model.new(width, height)
    local tabs: {string} = {}
    local preferences = appearance.defaults()
    local display = new_display(width, height)
    local updates = assert(display:updates())
    local presenter = ""
    local active, presenter_ready, broker_ready = false, false, false
    local presented = false
    local paused = false
    local last_rows: {string} = {}
    local initial_opened, quitting = false, false
    local requested_rejoin = false
    local binding = ""
    local fatal: string? = nil
    local deadline_ticks, recoveries = 0, 0
    local ticker = assert(time.ticker("100ms"))
    local ticks = ticker:channel()

    local function broker_request(op: string, definition_id: string, id: string, recipient: string)
        local request_id = uuid.v7()
        process.send(broker, "bee.app.request", {request_id = request_id, op = op,
            definition_id = definition_id, id = id, recipient = recipient})
        return request_id
    end
    local function send_scene()
        if active then process.send(presenter, "bee.desktop.scene", {scene = scene, tabs = tabs, preferences = preferences}) end
    end
    local function send_settings_state()
        if broker_ready then
            local theme = appearance.theme(preferences.theme)
            process.send(broker, "bee.settings.state", {theme = preferences.theme, background = preferences.background,
                page_foreground = theme.text, page_background = theme.surface})
        end
    end
    local function spawn_presenter()
        local grant = assert(display:grant())
        presenter = tostring(assert(process.with_options({terminal = grant}):with_scope(presenter_scope)
            :spawn_monitored("bee.terminal:main", "bee:workers", owner, initial_application, secondary_application)))
        active, presenter_ready = false, false
        paused = false
        binding = ""
        presented = false
        deadline_ticks = 0
    end
    local function recovery_screen()
        local canvas = tty.canvas(width, height)
        canvas:clear(" ")
        for y = 1, height do canvas:put(1, y, last_rows[y] or "", width) end
        canvas:put(1, height, "\27[38;2;255;201;99;48;2;23;32;44m"
            .. " Desktop paused. F12 Retry / Ctrl+Q Exit" .. string.rep(" ", width) .. "\27[0m", width)
        output:present(canvas:rows(), {cursor = {x = 1, y = 1, visible = false}})
    end
    local function pause_presenter()
        active, paused, presenter_ready = false, true, false
        binding = ""
        broker_request("bind", "", "", "")
        local retiring = presenter
        presenter = "" -- Fence all late messages, including a timed-out process.
        if retiring ~= "" then process.terminate(retiring) end
        recovery_screen()
    end
    local function replace_presenter()
        display:close()
        display = new_display(width, height)
        updates = assert(display:updates())
        spawn_presenter()
    end
    local function bind_presenter()
        if broker_ready and presenter_ready then
            binding = broker_request("bind", "", "", presenter)
        end
    end
    spawn_presenter()
    while not quitting do
        local selected = channel.select({input:case_receive(), lifecycle:case_receive(), control:case_receive(),
            commands:case_receive(), requests:case_receive(), settings_requests:case_receive(), ready:case_receive(), replies:case_receive(),
            scenes:case_receive(), acknowledgements:case_receive(), updates:case_receive(), ticks:case_receive()})
        if not selected.ok then break end
        if selected.channel == lifecycle then
            local event = selected.value
            if event.kind == process.event.CANCEL then break end
            if event.kind == process.event.EXIT then
                local exited = tostring(event.from)
                if exited == session or exited == broker then fatal = "Workspace service exited"; break end
                if exited == presenter then
                    active = false
                    if not requested_rejoin then recoveries = recoveries + 1 end
                    requested_rejoin = false
                    if recoveries > 3 then pause_presenter()
                    else replace_presenter() end
                end
            end
        elseif selected.channel == control then
            local msg = selected.value
            if msg:from() == presenter then
                local data: unknown = msg:payload():data()
                if type(data) == "table" then
                    if data.op == "ready" and not presenter_ready then
                        presenter_ready = true; bind_presenter()
                    elseif data.op == "quit" then quitting = true
                    elseif data.op == "rejoin" and active then
                        requested_rejoin = true
                        active = false
                        broker_request("bind", "", "", "")
                        process.send(presenter, "bee.workspace.retire", {})
                        -- The presenter closes only its own attachments and exits.
                        -- EXIT is the fence before a fresh producer is spawned.
                    end
                end
            end
        elseif selected.channel == ready then
            if selected.value:from() == broker then broker_ready = true; bind_presenter() end
        elseif selected.channel == requests then
            if selected.value:from() == presenter and active then
                local data: unknown = selected.value:payload():data()
                if type(data) == "table" and (data.op == "open" or data.op == "close") then
                    process.send(broker, "bee.app.request", data)
                end
            end
        elseif selected.channel == settings_requests then
            if selected.value:from() == broker then
                local data: unknown = selected.value:payload():data()
                if type(data) == "table" and data.definition_id == "bee.settings:app" and type(data.id) == "string"
                    and type(data.theme) == "string" and type(data.background) == "string" then
                    local next_preferences = appearance.decode({theme = data.theme, background = data.background})
                    if next_preferences then
                        preferences = next_preferences
                        send_settings_state()
                    else
                        -- The broker authenticates the sender; the workspace
                        -- still owns the complete appearance value set.
                        send_settings_state()
                    end
                end
            end
        elseif selected.channel == commands then
            if selected.value:from() == presenter and active then
                local data: unknown = selected.value:payload():data()
                -- Application lifecycle alone creates/removes logical windows.
                if type(data) == "table" and (data.op == "focus" or data.op == "place" or data.op == "fullscreen"
                    or data.op == "minimize" or data.op == "collapse" or data.op == "restore" or data.op == "snap") then
                    process.send(session, "bee.desktop.command", data)
                end
            end
        elseif selected.channel == replies then
            if selected.value:from() == broker then
                local reply = decode.reply(selected.value:payload():data())
                if reply then
                    if reply.op == "bind" and reply.request_id == binding then
                        active = true
                        send_settings_state()
                        process.send(session, "bee.desktop.command", {op = "snapshot"})
                        if not initial_opened then
                            initial_opened = true
                            if initial_application and initial_application ~= "" then broker_request("open", initial_application, "", "") end
                        end
                    elseif reply.op == "page" then send_scene()
                    elseif reply.op == "open" and reply.error == "" then
                        tabs[#tabs + 1] = reply.id
                        process.send(session, "bee.desktop.command", {op = "add", id = reply.id,
                            instance_id = reply.instance_id, title = reply.title})
                    elseif reply.op == "focus" and reply.error == "" then
                        process.send(session, "bee.desktop.command", {op = "focus", id = reply.id})
                        send_settings_state()
                    elseif (reply.op == "close" and reply.error == "") or reply.op == "closed" then
                        for i = #tabs, 1, -1 do if tabs[i] == reply.id then table.remove(tabs, i) end end
                        process.send(session, "bee.desktop.command", {op = "remove", id = reply.id})
                    end
                    if reply.op == "attached" then
                        if reply.request_id == binding then process.send(presenter, "bee.app.reply", reply) end
                    elseif reply.op ~= "bind" and active then process.send(presenter, "bee.app.reply", reply) end
                end
            end
        elseif selected.channel == acknowledgements then
            if selected.value:from() == session and active then
                local ack = decode.ack(selected.value:payload():data())
                if ack then process.send(presenter, "bee.desktop.ack", ack) end
            end
        elseif selected.channel == scenes then
            if selected.value:from() == session then
                local next_scene = decode.scene(selected.value:payload():data())
                if next_scene then
                    scene = next_scene
                    send_scene()
                end
            end
        elseif selected.channel == updates then
            local snapshot = display:snapshot()
            if active and snapshot and #snapshot.rows == height then
                output:present(snapshot.rows, {cursor = snapshot.cursor})
                last_rows = snapshot.rows
                presented = true
                deadline_ticks = 0
            end
        elseif selected.channel == ticks then
            if not paused and (not active or not presented) then
                deadline_ticks = deadline_ticks + 1
                if deadline_ticks >= 50 then pause_presenter() end
            end
        elseif selected.channel == input then
            local event = decode_input.decode(selected.value)
            if event then
                if event.type == "close" then break end
                if event.type == "key" and event.ctrl and event.key == "q" and event.action ~= "release" then break end
                if paused and event.type == "key" and event.key_type == "f12" and event.action ~= "release" then
                    recoveries = 0
                    replace_presenter()
                end
                if event.type == "resize" then
                    width, height = event.width, event.height
                    display:resize(width, height)
                    process.send(session, "bee.desktop.command", {op = "screen", width = width, height = height})
                    if paused then recovery_screen() end
                elseif active then
                    display:send(event)
                end
            end
        end
    end
    ticker:stop()
    broker_request("shutdown", "", "", "")
    process.send(session, "bee.desktop.command", {op = "shutdown"})
    if presenter ~= "" then process.terminate(presenter) end
    process.unlisten(settings_requests)
    display:close()
    output:close()
    tty.stop()
    if fatal then error(fatal) end
end
return {main = main}
