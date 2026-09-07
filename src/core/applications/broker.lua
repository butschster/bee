-- Private application authority. Only its workspace owner can issue requests.
-- Definition admission comes only from the protected host declaration.
local process = require("process")
local security = require("security")
local channel = require("channel")
local tty = require("tty")
local uuid = require("uuid")
local registry = require("registry")

type Instance = {id: string, instance_id: string, pid: string, view: tty.Viewport, title: string, mount: string, definition_id: string}
type Request = {request_id: string, op: string, definition_id: string, id: string, recipient: string, foreground: string, background: string}
type Reply = {request_id: string, op: string, id: string, instance_id: string, title: string, mount: string, error: string}
type SettingsRequest = {request_id: string, op: string, theme: string, background: string}

local function request(value: unknown): Request?
    if type(value) ~= "table" then return nil end
    if type(value.request_id) ~= "string" or type(value.op) ~= "string"
        or type(value.definition_id) ~= "string" or type(value.id) ~= "string" then return nil end
    if #value.request_id > 80 or #value.definition_id > 160 or #value.id > 80 then return nil end
    local recipient = ""
    if type(value.recipient) == "string" then recipient = value.recipient end
    return {request_id = value.request_id, op = value.op, definition_id = value.definition_id, id = value.id, recipient = recipient,
        foreground = type(value.foreground) == "string" and value.foreground or "",
        background = type(value.background) == "string" and value.background or ""}
end

local function settings_request(value: unknown): SettingsRequest?
    if type(value) ~= "table" or type(value.request_id) ~= "string" or type(value.op) ~= "string" then return nil end
    if #value.request_id > 80 or #value.op > 24 then return nil end
    if value.op == "state" then return {request_id = value.request_id, op = value.op, theme = "", background = ""} end
    if value.op ~= "set" and value.op ~= "appearance" then return nil end
    if type(value.theme) ~= "string" or type(value.background) ~= "string"
        or #value.theme > 80 or #value.background > 80 then return nil end
    local theme, background = tostring(value.theme), tostring(value.background)
    return {request_id = value.request_id, op = value.op, theme = theme, background = background}
end

local function main(owner: string)
    local requests = assert(process.listen("bee.app.request", {message = true}))
    local settings_requests = assert(process.listen("bee.settings.request", {message = true}))
    local settings_states = assert(process.listen("bee.settings.state", {message = true}))
    local lifecycle = assert(process.events())
    assert(process.monitor(owner))
    local instances: {[string]: Instance} = {}
    local recipient = ""
    local foreground, background = "#d8e2ef", "#17202c"
    local settings_theme, settings_background = "honey", "dots"
    local app_policy, app_policy_error = security.policy("bee:app_policy")
    if app_policy_error then error(tostring(app_policy_error)) end
    local app_scope = security.new_scope({app_policy})
    local settings_policy, settings_policy_error = security.policy("bee:settings_policy")
    if settings_policy_error then error(tostring(settings_policy_error)) end
    local settings_scope = security.new_scope({settings_policy})
    local processes_policy, processes_error = security.policy("bee:processes_policy")
    if processes_error then error(tostring(processes_error)) end
    local processes_scope = security.new_scope({settings_policy, processes_policy})
    local process_requests = assert(process.listen("bee.processes.request", {message = true}))
    local function send_settings_state(item: Instance)
        process.send(item.pid, "bee.settings.state", {theme = settings_theme, background = settings_background})
    end
    local function dispose(id: string)
        local item = instances[id]
        if item then
            instances[id] = nil
            item.view:send({type = "close"})
            process.terminate(item.pid)
            item.view:close()
        end
    end
    assert(process.send(owner, "bee.app.ready", {}))
    while true do
        local selected = channel.select({requests:case_receive(), settings_requests:case_receive(), settings_states:case_receive(), process_requests:case_receive(), lifecycle:case_receive()})
        if not selected.ok then break end
        if selected.channel == lifecycle then
            local event = selected.value
            if event.kind == process.event.CANCEL then break end
            if event.kind == process.event.EXIT and tostring(event.from) == owner then break end
            if event.kind == process.event.EXIT then
                for id, item in pairs(instances) do
                    if item.pid == tostring(event.from) then
                        dispose(id)
                        process.send(owner, "bee.app.reply", {request_id = "", op = "closed", id = id,
                            instance_id = "", title = "", mount = "", error = "Application exited"})
                    end
                end
            end
        elseif selected.channel == settings_states then
            local msg = selected.value
            if msg:from() == owner then
                local value = msg:payload():data()
                if type(value) == "table" and type(value.theme) == "string" and type(value.background) == "string"
                    and #value.theme <= 80 and #value.background <= 80 then
                    settings_theme, settings_background = value.theme, value.background
                    if type(value.page_foreground) == "string" and type(value.page_background) == "string" then
                        foreground, background = value.page_foreground, value.page_background
                        for _, item in pairs(instances) do
                            local view = item.view
                            if view then view:set_page({foreground = foreground, background = background}) end
                        end
                    end
                    for _, item in pairs(instances) do
                        if item.definition_id == "bee.settings:app" or item.definition_id == "bee.processes:app" then send_settings_state(item) end
                    end
                    process.send(owner, "bee.app.reply", {request_id = "", op = "page", id = "",
                        instance_id = "", title = "", mount = "", error = ""})
                end
            end
        elseif selected.channel == process_requests then
            local msg = selected.value
            local sender = tostring(msg:from())
            local admitted = false
            for _, item in pairs(instances) do
                if item.pid == sender and item.definition_id == "bee.processes:app" then admitted = true; break end
            end
            local data: unknown = msg:payload():data()
            if admitted and type(data) == "table" and data.op == "close"
                and type(data.pid) == "string" and #data.pid <= 160
                and type(data.request_id) == "string" and #data.request_id <= 80 then
                local target: Instance? = nil
                for _, item in pairs(instances) do if item.pid == data.pid then target = item; break end end
                local err = "Core processes are protected"
                if target then
                    dispose(target.id)
                    process.send(owner, "bee.app.reply", {request_id = "", op = "closed", id = target.id,
                        instance_id = target.instance_id, title = target.title, mount = "", error = ""})
                    err = ""
                end
                process.send(sender, "bee.processes.reply", {request_id = data.request_id, error = err})
            end
        elseif selected.channel == settings_requests then
            local msg = selected.value
            local sender = tostring(msg:from())
            local item: Instance? = nil
            for _, candidate in pairs(instances) do
                if candidate.pid == sender and (candidate.definition_id == "bee.settings:app" or candidate.definition_id == "bee.processes:app") then item = candidate; break end
            end
            local req = settings_request(msg:payload():data())
            if item and req then
                if req.op == "state" then
                    send_settings_state(item)
                elseif item.definition_id == "bee.settings:app" then
                    process.send(owner, "bee.settings.request", {request_id = req.request_id, op = req.op,
                        definition_id = "bee.settings:app", id = item.id, instance_id = item.instance_id,
                        theme = req.theme, background = req.background})
                end
            end
        else
            local msg = selected.value
            if msg:from() == owner then
                local payload = msg:payload()
                local req = request(payload:data())
                if req then
                    if req.op == "shutdown" then break end
                    local reply: Reply = {request_id = req.request_id, op = req.op, id = req.id,
                        instance_id = "", title = "", mount = "", error = ""}
                    if req.op == "bind" then
                        -- Revoke the entire previous attachment before granting any
                        -- authority to the new PID. Producers and view IDs survive.
                        for _, item in pairs(instances) do
                            local view = item.view
                            if view and item.mount ~= "" then view:revoke(item.mount); item.mount = "" end
                        end
                        recipient = req.recipient
                        if recipient ~= "" then
                            for id, item in pairs(instances) do
                                local view = item.view
                                if view then
                                    local mount, err = view:mount(recipient, {observe = true, input = true, resize = true})
                                    item.mount = mount or ""
                                    process.send(owner, "bee.app.reply", {request_id = req.request_id, op = "attached", id = id,
                                        instance_id = item.instance_id, title = item.title, mount = item.mount, error = err and tostring(err) or ""})
                                end
                            end
                        end
                    elseif req.op == "page" then
                        foreground, background = req.foreground, req.background
                        for _, item in pairs(instances) do
                            local view = item.view
                            if view then
                                local _, err = view:set_page({foreground = foreground, background = background})
                                if err then reply.error = tostring(err) end
                            end
                        end
                    elseif req.op == "close" then
                        dispose(req.id)
                    elseif req.op == "open" then
                        local existing: Instance? = nil
                        if req.definition_id == "bee.settings:app" or req.definition_id == "bee.processes:app" then
                            for _, item in pairs(instances) do
                                if item.definition_id == req.definition_id then existing = item; break end
                            end
                        end
                        if existing then
                            reply.op, reply.id, reply.instance_id = "focus", existing.id, existing.instance_id
                            reply.title, reply.mount = existing.title, existing.mount
                            send_settings_state(existing)
                        else
                        local count = 0
                        for _ in pairs(instances) do count = count + 1 end
                        local admission = registry.get("bee:application_admission")
                        local allowed = false
                        if admission and type(admission.data) == "table" and type(admission.data.definitions) == "table" then
                            for _, id in ipairs(admission.data.definitions) do
                                if id == req.definition_id then allowed = true; break end
                            end
                        end
                        if recipient == "" then reply.error = "Desktop is not attached"
                        elseif not allowed then reply.error = "Application is not admitted"
                        elseif count >= 16 then reply.error = "Desktop instance limit reached"
                        else
                            local entry = registry.get(req.definition_id)
                            if not entry or entry.kind ~= "process.lua" or entry.meta.type ~= "bee.application"
                                or type(entry.meta.application) ~= "table"
                                or entry.meta.application.api_version ~= 1 or entry.meta.application.lifetime ~= "view"
                                or type(entry.meta.application.title) ~= "string" then
                                reply.error = "Application definition is unavailable"
                            else
                                local view, err = tty.viewport({width = 60, height = 16,
                                    page = {foreground = foreground, background = background}})
                                if not view then reply.error = tostring(err)
                                else
                                    local grant, grant_err = view:grant()
                                    if not grant then reply.error = tostring(grant_err); view:close()
                                    else
                                        local scope = app_scope
                                        if req.definition_id == "bee.settings:app" then scope = settings_scope
                                        elseif req.definition_id == "bee.processes:app" then scope = processes_scope end
                                        -- The first app argument is this broker's PID.  Settings uses it
                                        -- as its only authenticated write route; the owner remains a
                                        -- second argument for applications that need lifecycle context.
                                        local pid, spawn_err = process.with_options({terminal = grant}):with_scope(scope)
                                            :spawn_monitored(req.definition_id, "bee:workers", tostring(process.pid()), owner)
                                        if not pid then reply.error = tostring(spawn_err); view:close()
                                        else
                                            local mount, mount_err = view:mount(recipient, {observe = true, input = true, resize = true})
                                            if not mount then
                                                process.terminate(tostring(pid)); view:close(); reply.error = tostring(mount_err)
                                            else
                                                local id, instance_id = uuid.v7(), uuid.v7()
                                                instances[id] = {id = id, instance_id = instance_id, pid = tostring(pid), view = view,
                                                    title = entry.meta.application.title, mount = mount, definition_id = req.definition_id}
                                                reply.id, reply.instance_id, reply.mount = id, instance_id, mount
                                                reply.title = entry.meta.application.title
                                                if req.definition_id == "bee.settings:app" or req.definition_id == "bee.processes:app" then
                                                    local created = instances[id]
                                                    if created then send_settings_state(created) end
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                        end
                    else reply.error = "Unknown application operation" end
                    process.send(owner, "bee.app.reply", reply)
                end
            end
        end
    end
    for id in pairs(instances) do dispose(id) end
    process.unlisten(requests)
    process.unlisten(settings_requests)
    process.unlisten(settings_states)
end
return {main = main}
