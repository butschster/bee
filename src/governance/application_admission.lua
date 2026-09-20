-- MIT. Canonical host-selected application admission carried by one governed
-- overlay. This module is pure: it reads no registry state and grants no
-- capability. Activation and the application catalog separately decide when
-- a measured record is trusted.
local canonical = require("canonical")
local hash = require("hash")
local bounds = require("bounds")

local M = {}

M.SCHEMA = "bee.governance-application-admission@1"
M.MAX_BINDINGS = 64
M.MAX_POLICIES = 16
M.MAX_BYTES = 65536
M.RESERVED_PREFIX = "bee.governance:admission."

type Object = {[string]: unknown}
type ThreadAccess = "none" | "observe_post"
type Binding = {definition_id: string, policies: {string}, thread_access: ThreadAccess}
type Record = {schema_revision: string, workspace_id: string, overlay_owner: string,
    source_node: string, source_workspace: string, artifact_digest: string,
    policy_digest: string, bindings: {Binding}}
type Measurement = {record: Record, bytes: string, digest: string}

local function sha(value: unknown): string?
    if type(value) ~= "string" or #value ~= 64 or not value:match("^[0-9a-f]+$") then return nil end
    return value
end

local function registry_id(value: unknown): string?
    local id = bounds.id(value)
    if not id or not id:match("^[A-Za-z0-9][A-Za-z0-9_.-]*:[A-Za-z0-9][A-Za-z0-9_.-]*$") then return nil end
    return id
end

local function dense(raw: unknown, label: string, maximum: integer): (table?, integer?, string?)
    if type(raw) ~= "table" then return nil, nil, label .. " must be a list" end
    local count = 0
    for key in pairs(raw :: table) do
        if type(key) ~= "number" or key ~= math.floor(key :: number) or (key :: number) < 1 then
            return nil, nil, label .. " must be a dense list"
        end
        count = count + 1
    end
    if count > maximum then return nil, nil, label .. " exceeds its bound" end
    for index = 1, count do
        if (raw :: table)[index] == nil then return nil, nil, label .. " must be a dense list" end
    end
    return raw :: table, count, nil
end

local function thread_access(raw: unknown): ThreadAccess?
    if raw == nil or raw == "none" then return "none" end
    if raw == "observe_post" then return "observe_post" end
    return nil
end

local function binding(raw: unknown): (Binding?, string?)
    local value = bounds.object(raw)
    if not value then return nil, "application binding must be an object" end
    local extra = bounds.fields(value, {"definition_id", "policies", "thread_access"})
    if extra then return nil, "application binding: " .. extra end
    local definition_id = registry_id(value.definition_id)
    local access = thread_access(value.thread_access)
    local rows, count, rows_error = dense(value.policies, "application policies", M.MAX_POLICIES)
    if not definition_id or not access or not rows or count == nil then
        return nil, rows_error or "application binding is invalid"
    end
    -- Preallocate an array slot even for zero rows so canonical JSON retains
    -- the empty-list shape rather than turning it into an object.
    local capacity: integer = count
    if capacity < 1 then capacity = 1 end
    local policies: {string} = table.create(capacity, 0)
    local seen: {[string]: boolean} = {}
    for index = 1, count do
        local policy = registry_id(rows[index])
        if not policy or seen[policy] then return nil, "application policies contain an invalid or duplicate value" end
        seen[policy] = true
        policies[index] = policy
    end
    table.sort(policies)
    return {definition_id = definition_id, policies = policies, thread_access = access}, nil
end

function M.bindings(raw: unknown): ({Binding}?, string?)
    local rows, count, rows_error = dense(raw, "applications", M.MAX_BINDINGS)
    if not rows or count == nil then return nil, rows_error end
    local capacity: integer = count
    if capacity < 1 then capacity = 1 end
    local result: {Binding} = table.create(capacity, 0)
    local seen: {[string]: boolean} = {}
    for index = 1, count do
        local item, item_error = binding(rows[index])
        if not item then return nil, item_error end
        if seen[item.definition_id] then return nil, "application definition is duplicated" end
        seen[item.definition_id] = true
        result[index] = item
    end
    table.sort(result, function(left: Binding, right: Binding): boolean
        return left.definition_id < right.definition_id
    end)
    return result, nil
end

function M.record(raw: unknown): (Record?, string?)
    local value = bounds.object(raw)
    if not value then return nil, "application admission record must be an object" end
    local extra = bounds.fields(value, {"schema_revision", "workspace_id", "overlay_owner",
        "source_node", "source_workspace", "artifact_digest", "policy_digest", "bindings"})
    if extra then return nil, "application admission record: " .. extra end
    local workspace_id, overlay_owner = bounds.id(value.workspace_id), bounds.id(value.overlay_owner)
    local source_node, source_workspace = bounds.id(value.source_node), bounds.id(value.source_workspace)
    local artifact_digest, policy_digest = sha(value.artifact_digest), sha(value.policy_digest)
    local bindings, bindings_error = M.bindings(value.bindings)
    if value.schema_revision ~= M.SCHEMA or not workspace_id or not overlay_owner
        or not source_node or not source_workspace or not artifact_digest or not policy_digest or not bindings then
        return nil, bindings_error or "application admission record is invalid"
    end
    return {schema_revision = M.SCHEMA, workspace_id = workspace_id, overlay_owner = overlay_owner,
        source_node = source_node, source_workspace = source_workspace,
        artifact_digest = artifact_digest, policy_digest = policy_digest, bindings = bindings}, nil
end

function M.id(owner_raw: unknown): (string?, string?)
    local owner = bounds.id(owner_raw)
    if not owner then return nil, "application admission overlay owner is invalid" end
    local digest, digest_error = hash.sha256(owner)
    if not digest then return nil, tostring(digest_error or "measure application admission owner") end
    return M.RESERVED_PREFIX .. digest, nil
end

function M.measure(raw: unknown): (Measurement?, string?)
    local record, record_error = M.record(raw)
    if not record then return nil, record_error end
    local bytes, encode_error = canonical.encode(record, M.MAX_BYTES)
    if not bytes then return nil, tostring(encode_error or "encode application admission") end
    local digest, digest_error = hash.sha256(bytes)
    if not digest then return nil, tostring(digest_error or "measure application admission") end
    return {record = record, bytes = bytes, digest = digest}, nil
end

return M
