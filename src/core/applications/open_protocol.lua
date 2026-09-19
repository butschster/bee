-- MIT. The bounded bridge between an admitted agent open call and the
-- existing workspace host/broker request path.
local arguments = require("arguments")
local decode = require("decode")
local contract = require("contract")
local M = {}
type Request = {version: integer, workspace_id: string, request_id: string, definition_id: string, arguments: {string}}
type Reply = {request_id: string, reply: contract.Reply}

local function text(value: unknown, limit: integer): string?
    if type(value) ~= "string" or value == "" or #value > limit or value:find("%c") then return nil end
    return value
end

function M.request(value: unknown, workspace_id: string): Request?
    if type(value) ~= "table" or value.version ~= 1 or value.workspace_id ~= workspace_id then return nil end
    for key in pairs(value) do
        if key ~= "version" and key ~= "workspace_id" and key ~= "request_id"
            and key ~= "definition_id" and key ~= "arguments" then return nil end
    end
    local request_id = text(value.request_id, 80)
    local definition_id = text(value.definition_id, 160)
    local args = arguments.decode(value.arguments)
    if not request_id or not definition_id or not args then return nil end
    return {version = 1, workspace_id = workspace_id, request_id = request_id,
        definition_id = definition_id, arguments = args}
end

-- The host forwards the broker's typed application reply and adds only the
-- workspace/request identity needed to route it back to the exact caller.
function M.reply(value: unknown, workspace_id: string): Reply?
    if type(value) ~= "table" or value.version ~= 1 or value.workspace_id ~= workspace_id then return nil end
    for key in pairs(value) do
        if key ~= "version" and key ~= "workspace_id" and key ~= "request_id" and key ~= "reply" then return nil end
    end
    local request_id = text(value.request_id, 80)
    local reply = type(value.reply) == "table" and decode.reply(value.reply) or nil
    if not request_id or not reply or reply.request_id ~= request_id or reply.workspace_id ~= workspace_id then return nil end
    return {request_id = request_id, reply = reply}
end

return M
