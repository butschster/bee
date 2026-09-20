-- MIT. Internal workspace-owned application/thread binding persistence.
--
-- A row names one logical application instance and the thread it is bound to.
-- The application is a participant in that thread.  The
-- workspace owner is the only caller of this helper; thread membership and
-- physical execution remain outside this store.
local workspace_store = require("workspace_store")

type WorkspaceStore = workspace_store.Store
type State = "pending" | "active" | "revoked"
type Binding = {
    instance_id: string,
    thread_id: string,
    definition_id: string,
    actor_id: string,
    role: "participant",
    binding_revision: integer,
    state: State,
    idempotency_key: string,
}
type PrepareRequest = {
    instance_id: string,
    thread_id: string,
    definition_id: string,
    actor_id: string,
    role: "participant",
    idempotency_key: string,
}
type TransitionRequest = {instance_id: string, expected_revision: integer, expected_state: State}
type Store = {
    workspace: WorkspaceStore,
    prepare: (Store, unknown) -> (Binding?, string?),
    activate: (Store, unknown) -> (Binding?, string?),
    revoke: (Store, unknown) -> (Binding?, string?),
    get: (Store, unknown) -> (Binding?, string?),
    list: (Store) -> ({Binding}?, string?),
}

local M = {}
local MAX_INSTANCE_ID = 80
local MAX_THREAD_ID = 160
local MAX_DEFINITION_ID = 160
local MAX_ACTOR_ID = 160
local MAX_IDEMPOTENCY_KEY = 160
local MAX_REVISION = 9007199254740990
local MAX_BINDINGS = 256

local function text(value: unknown, maximum: integer): string?
    if type(value) ~= "string" or #value == 0 or #value > maximum or value:find("[^ -~]") then return nil end
    return value
end

local function revision(value: unknown): integer?
    if type(value) ~= "number" or value ~= value or value ~= math.floor(value)
        or value < 1 or value > MAX_REVISION then return nil end
    return math.floor(value)
end

local function object(value: unknown): {[string]: unknown}?
    if type(value) ~= "table" then return nil end
    for key in pairs(value) do
        if type(key) ~= "string" then return nil end
    end
    return value :: {[string]: unknown}
end

local function fields(value: {[string]: unknown}, allowed: {string}): boolean
    local permitted: {[string]: boolean} = {}
    for _, name in ipairs(allowed) do permitted[name] = true end
    for key in pairs(value) do
        if not permitted[key] then return false end
    end
    return true
end

local function role(value: unknown): "participant"?
    if value == "participant" then return "participant" end
    return nil
end

local function state(value: unknown): State?
    if value == "pending" or value == "active" or value == "revoked" then return value end
    return nil
end

local function prepare_input(value: unknown): (PrepareRequest?, string?)
    local input = object(value)
    if not input or not fields(input, {"instance_id", "thread_id", "definition_id", "actor_id", "role", "idempotency_key"}) then
        return nil, "invalid application thread binding prepare"
    end
    local instance_id = text(input.instance_id, MAX_INSTANCE_ID)
    local thread_id = text(input.thread_id, MAX_THREAD_ID)
    local definition_id = text(input.definition_id, MAX_DEFINITION_ID)
    local actor_id = text(input.actor_id, MAX_ACTOR_ID)
    local binding_role = role(input.role)
    local idempotency_key = text(input.idempotency_key, MAX_IDEMPOTENCY_KEY)
    if not instance_id or not thread_id or not definition_id or not actor_id or not binding_role or not idempotency_key then
        return nil, "invalid application thread binding identity"
    end
    return {instance_id = instance_id, thread_id = thread_id, definition_id = definition_id,
        actor_id = actor_id, role = binding_role, idempotency_key = idempotency_key}, nil
end

local function transition_input(value: unknown, operation: string): (TransitionRequest?, string?)
    local input = object(value)
    if not input or not fields(input, {"instance_id", "expected_revision", "expected_state"}) then
        return nil, "invalid application thread binding " .. operation
    end
    local instance_id = text(input.instance_id, MAX_INSTANCE_ID)
    local expected_revision = revision(input.expected_revision)
    local expected_state = state(input.expected_state)
    if not instance_id or not expected_revision or not expected_state then
        return nil, "invalid application thread binding transition"
    end
    return {instance_id = instance_id, expected_revision = expected_revision, expected_state = expected_state}, nil
end

local function instance_key(value: unknown): string?
    if type(value) == "string" then return text(value, MAX_INSTANCE_ID) end
    local input = object(value)
    if not input or not fields(input, {"instance_id"}) then return nil end
    return text(input.instance_id, MAX_INSTANCE_ID)
end

local function integer(value: unknown): integer?
    if type(value) ~= "number" or value ~= value or value ~= math.floor(value) then return nil end
    return math.floor(value)
end

local function decode(row: {[string]: unknown}): Binding?
    local instance_id = text(row.instance_id, MAX_INSTANCE_ID)
    local thread_id = text(row.thread_id, MAX_THREAD_ID)
    local definition_id = text(row.definition_id, MAX_DEFINITION_ID)
    local actor_id = text(row.actor_id, MAX_ACTOR_ID)
    local binding_role = role(row.role)
    local binding_revision = revision(row.binding_revision)
    local binding_state = state(row.state)
    local idempotency_key = text(row.idempotency_key, MAX_IDEMPOTENCY_KEY)
    if not instance_id or not thread_id or not definition_id or not actor_id or not binding_role
        or not binding_revision or not binding_state or not idempotency_key then return nil end
    return {instance_id = instance_id, thread_id = thread_id, definition_id = definition_id,
        actor_id = actor_id, role = binding_role, binding_revision = binding_revision,
        state = binding_state, idempotency_key = idempotency_key}
end

local function select_sql(): string
    return "SELECT instance_id, thread_id, definition_id, actor_id, role, binding_revision, state, idempotency_key " ..
        "FROM workspace_application_thread_bindings"
end

local function same_identity(existing: Binding, requested: PrepareRequest): boolean
    return existing.instance_id == requested.instance_id and existing.thread_id == requested.thread_id
        and existing.definition_id == requested.definition_id and existing.actor_id == requested.actor_id
        and existing.role == requested.role and existing.idempotency_key == requested.idempotency_key
end

local function rollback(tx: sql.Transaction)
    tx:rollback()
end

function M.open(workspace: WorkspaceStore): (Store?, string?)
    if type(workspace) ~= "table" or workspace.db == nil then
        return nil, "application thread binding store requires workspace storage"
    end
    return {workspace = workspace, prepare = M.prepare, activate = M.activate, revoke = M.revoke,
        get = M.get, list = M.list}, nil
end

function M.prepare(store: Store, value: unknown): (Binding?, string?)
    local request, input_error = prepare_input(value)
    if not request then return nil, input_error end
    local tx, begin_error = store.workspace.db:begin()
    if not tx then return nil, "begin application thread binding prepare: " .. tostring(begin_error) end

    local rows, query_error = tx:query(select_sql() .. " WHERE instance_id = ? LIMIT 2", {request.instance_id})
    if query_error or not rows then
        rollback(tx)
        return nil, "read application thread binding: " .. tostring(query_error)
    end
    if #rows > 1 then
        rollback(tx)
        return nil, "application thread binding is corrupt"
    end
    if #rows == 1 then
        local existing = decode(rows[1])
        if not existing then
            rollback(tx)
            return nil, "application thread binding is corrupt"
        end
        local _, commit_error = tx:commit()
        if commit_error then
            rollback(tx)
            return nil, "commit application thread binding replay: " .. tostring(commit_error)
        end
        if same_identity(existing, request) then return existing, nil end
        return nil, "application thread binding conflicts with immutable identity"
    end

    local key_rows, key_error = tx:query(select_sql() .. " WHERE idempotency_key = ? LIMIT 2", {request.idempotency_key})
    if key_error or not key_rows then
        rollback(tx)
        return nil, "read application thread binding idempotency key: " .. tostring(key_error)
    end
    if #key_rows > 1 then
        rollback(tx)
        return nil, "application thread binding is corrupt"
    end
    if #key_rows == 1 then
        rollback(tx)
        return nil, "application thread binding idempotency key conflicts with another instance"
    end

    local count_rows, count_error = tx:query(
        "SELECT COUNT(*) AS count FROM workspace_application_thread_bindings WHERE state IN ('pending', 'active')")
    if count_error or not count_rows or #count_rows ~= 1 or integer(count_rows[1].count) == nil then
        rollback(tx)
        return nil, "count active application thread bindings: " .. tostring(count_error)
    end
    if integer(count_rows[1].count) >= MAX_BINDINGS then
        rollback(tx)
        return nil, "application thread binding capacity reached"
    end

    local _, insert_error = tx:execute(
        "INSERT INTO workspace_application_thread_bindings " ..
        "(instance_id, thread_id, definition_id, actor_id, role, binding_revision, state, idempotency_key) " ..
        "VALUES (?, ?, ?, ?, ?, 1, 'pending', ?)",
        {request.instance_id, request.thread_id, request.definition_id, request.actor_id, request.role, request.idempotency_key})
    if insert_error then
        rollback(tx)
        return nil, "prepare application thread binding: " .. tostring(insert_error)
    end
    local _, commit_error = tx:commit()
    if commit_error then
        rollback(tx)
        return nil, "commit application thread binding prepare: " .. tostring(commit_error)
    end
    return {instance_id = request.instance_id, thread_id = request.thread_id, definition_id = request.definition_id,
        actor_id = request.actor_id, role = request.role, binding_revision = 1, state = "pending",
        idempotency_key = request.idempotency_key}, nil
end

function M.activate(store: Store, value: unknown): (Binding?, string?)
    local request, input_error = transition_input(value, "activation")
    if not request then return nil, input_error end
    local expected_revision: integer = request.expected_revision
    local expected_state: State = request.expected_state
    if expected_state ~= "pending" then return nil, "application thread binding activation requires pending state" end
    if expected_revision >= MAX_REVISION then return nil, "application thread binding revision exhausted" end

    local tx, begin_error = store.workspace.db:begin()
    if not tx then return nil, "begin application thread binding activation: " .. tostring(begin_error) end
    local rows, query_error = tx:query(select_sql() .. " WHERE instance_id = ? LIMIT 2", {request.instance_id})
    if query_error or not rows then
        rollback(tx)
        return nil, "read application thread binding for activation: " .. tostring(query_error)
    end
    if #rows ~= 1 then
        rollback(tx)
        return nil, #rows == 0 and "application thread binding is missing" or "application thread binding is corrupt"
    end
    local existing = decode(rows[1])
    if not existing then
        rollback(tx)
        return nil, "application thread binding is corrupt"
    end
    if existing.state == "revoked" then
        rollback(tx)
        return nil, "application thread binding is revoked"
    end
    if existing.binding_revision ~= expected_revision or existing.state ~= expected_state then
        rollback(tx)
        return nil, "application thread binding revision or state changed"
    end

    local result, update_error = tx:execute(
        "UPDATE workspace_application_thread_bindings SET binding_revision = ?, state = 'active' " ..
        "WHERE instance_id = ? AND binding_revision = ? AND state = ?",
        {expected_revision + 1, request.instance_id, expected_revision, expected_state})
    if update_error or not result or integer(result.rows_affected) ~= 1 then
        rollback(tx)
        return nil, "application thread binding activation was stale"
    end
    local _, commit_error = tx:commit()
    if commit_error then
        rollback(tx)
        return nil, "commit application thread binding activation: " .. tostring(commit_error)
    end
    existing.binding_revision = expected_revision + 1
    existing.state = "active"
    return existing, nil
end

function M.revoke(store: Store, value: unknown): (Binding?, string?)
    local request, input_error = transition_input(value, "revocation")
    if not request then return nil, input_error end
    local expected_revision: integer = request.expected_revision
    local expected_state: State = request.expected_state
    if expected_state ~= "pending" and expected_state ~= "active" then
        return nil, "application thread binding revocation requires pending or active state"
    end
    if expected_revision >= MAX_REVISION then return nil, "application thread binding revision exhausted" end

    local tx, begin_error = store.workspace.db:begin()
    if not tx then return nil, "begin application thread binding revocation: " .. tostring(begin_error) end
    local rows, query_error = tx:query(select_sql() .. " WHERE instance_id = ? LIMIT 2", {request.instance_id})
    if query_error or not rows then
        rollback(tx)
        return nil, "read application thread binding for revocation: " .. tostring(query_error)
    end
    if #rows ~= 1 then
        rollback(tx)
        return nil, #rows == 0 and "application thread binding is missing" or "application thread binding is corrupt"
    end
    local existing = decode(rows[1])
    if not existing then
        rollback(tx)
        return nil, "application thread binding is corrupt"
    end
    if existing.state == "revoked" then
        rollback(tx)
        return nil, "application thread binding is already revoked"
    end
    if existing.binding_revision ~= expected_revision or existing.state ~= expected_state then
        rollback(tx)
        return nil, "application thread binding revision or state changed"
    end

    local result, update_error = tx:execute(
        "UPDATE workspace_application_thread_bindings SET binding_revision = ?, state = 'revoked' " ..
        "WHERE instance_id = ? AND binding_revision = ? AND state = ?",
        {expected_revision + 1, request.instance_id, expected_revision, expected_state})
    if update_error or not result or integer(result.rows_affected) ~= 1 then
        rollback(tx)
        return nil, "application thread binding revocation was stale"
    end
    local _, commit_error = tx:commit()
    if commit_error then
        rollback(tx)
        return nil, "commit application thread binding revocation: " .. tostring(commit_error)
    end
    existing.binding_revision = expected_revision + 1
    existing.state = "revoked"
    return existing, nil
end

function M.get(store: Store, value: unknown): (Binding?, string?)
    local instance_id = instance_key(value)
    if not instance_id then return nil, "invalid application thread binding key" end
    local rows, query_error = store.workspace.db:query(select_sql() .. " WHERE instance_id = ? LIMIT 2", {instance_id})
    if query_error or not rows then return nil, "read application thread binding: " .. tostring(query_error) end
    if #rows == 0 then return nil, nil end
    if #rows ~= 1 then return nil, "application thread binding is corrupt" end
    local result = decode(rows[1])
    if not result then return nil, "application thread binding is corrupt" end
    return result, nil
end

function M.list(store: Store): ({Binding}?, string?)
    local rows, query_error = store.workspace.db:query(
        select_sql() .. " WHERE state IN ('pending', 'active') ORDER BY instance_id LIMIT " .. tostring(MAX_BINDINGS + 1))
    if query_error or not rows then return nil, "list application thread bindings: " .. tostring(query_error) end
    if #rows > MAX_BINDINGS then return nil, "application thread binding capacity exceeded" end
    local result: {Binding} = {}
    for _, row in ipairs(rows) do
        local decoded = decode(row)
        if not decoded then return nil, "application thread binding is corrupt" end
        result[#result + 1] = decoded
    end
    return result, nil
end

return M
