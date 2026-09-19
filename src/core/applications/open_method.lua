-- MIT. Agent application opening is a small, explicitly admitted facade over
-- the existing workspace host and applications broker. It has no registry,
-- publication or activation authority.
local process = require("process")
local security = require("security")
local channel = require("channel")
local time = require("time")
local ctx = require("ctx")
local bounds = require("bounds")
local hash = require("hash")
local protocol = require("open_protocol")
local arguments = require("arguments")
local M = {}
local BINDING_KEY = "bee.gateway.binding"
local HOST_PREFIX = "bee.workspace.host/"
local MAX_WAIT_MS = 30000

local function fail(code: string, message: string): {[string]: unknown}
    return {ok = false, error = {code = code, message = message}}
end

local function attribution(): ({[string]: unknown}?, string?)
    local values, value_error = ctx.get(BINDING_KEY)
    if value_error then return nil, "the call context is unavailable" end
    local object = bounds.object(values)
    if not object then return nil, "the call is not bound to a gateway attempt" end
    return object, nil
end

local function request_id(action_id: string, idempotency_key: string): (string?, string?)
    local digest, digest_error = hash.sha256(action_id .. "\0" .. idempotency_key)
    if not digest then return nil, tostring(digest_error or "request identity failed") end
    return "agent-open-" .. digest:sub(1, 56), nil
end

function M.handle(raw: unknown): {[string]: unknown}
    local binding, binding_error = attribution()
    if not binding then return fail("UNAUTHENTICATED", binding_error or "gateway binding unavailable") end
    local action_id = bounds.id(binding.action_id)
    local workspace_id = bounds.id(binding.workspace_id)
    if not action_id or not workspace_id then return fail("UNAUTHENTICATED", "gateway binding has no action or workspace") end
    local object = bounds.object(raw)
    if not object then return fail("INVALID", "open request must be an object") end
    local extra = bounds.fields(object, {"definition_id", "arguments", "idempotency_key"})
    if extra then return fail("INVALID", extra) end
    local definition_id = bounds.id(object.definition_id)
    local idempotency_key = bounds.id(object.idempotency_key)
    local args = arguments.decode(object.arguments)
    if not definition_id then return fail("INVALID", "definition_id must be an identifier") end
    if not idempotency_key or #idempotency_key > 64 then return fail("INVALID", "idempotency_key must be a bounded identifier") end
    if not args then return fail("INVALID", "arguments must be bounded literal strings") end
    if not security.actor() then return fail("UNAUTHENTICATED", "the caller is not authenticated") end
    -- Catalog admission is destination-local. This prevents an agent from
    -- asking the host to open a definition that exists only in a staged or
    -- foreign registry view.
    local catalog = require("catalog")
    local admitted = false
    for _, binding in ipairs(catalog.bindings()) do
        if binding.definition_id == definition_id then admitted = true; break end
    end
    if not admitted or not catalog.descriptor(definition_id) then
        return fail("NOT_ADMITTED", "application is not applied and admitted in this workspace")
    end
    local request, request_error = request_id(action_id, idempotency_key)
    if not request then return fail("INVALID", request_error or "request identity failed") end
    local host, lookup_error = process.registry.lookup(HOST_PREFIX .. workspace_id)
    if not host then return fail("UNAVAILABLE", "workspace host is unavailable: " .. tostring(lookup_error or "not registered")) end
    local replies, listen_error = process.listen("bee.host.application.reply", {message = true})
    if not replies then return fail("UNAVAILABLE", tostring(listen_error or "open reply channel unavailable")) end
    local sent, send_error = process.send(host, "bee.host.application", {version = 1, workspace_id = workspace_id,
        request_id = request, definition_id = definition_id, arguments = args})
    if not sent then process.unlisten(replies); return fail("UNAVAILABLE", tostring(send_error or "workspace host rejected request")) end
    local deadline = time.after(tostring(MAX_WAIT_MS) .. "ms")
    local reply: protocol.Reply? = nil
    while true do
        local selected = channel.select({replies:case_receive(), deadline:case_receive()})
        if not selected.ok or selected.channel == deadline then break end
        if selected.value:from() == tostring(host) then
            local candidate = protocol.reply(selected.value:payload():data(), workspace_id)
            if candidate and candidate.request_id == request then
                reply = candidate
                break
            end
        end
    end
    process.unlisten(replies)
    if not reply then return fail("UNAVAILABLE", "workspace host did not answer") end
    local result = reply.reply
    if result.error_code ~= "" then return fail(result.error_code, result.error) end
    return {ok = true, value = {workspace_id = workspace_id, definition_id = result.definition_id,
        id = result.id, instance_id = result.instance_id, title = result.title, replayed = result.op == "focus"}}
end

return {handle = M.handle}
