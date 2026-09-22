-- MIT. Gateway method inbox_settle: the harness answered, so close the
-- delivery in both places.
--
-- The thread is the authority and the queue row is the evidence, so the
-- thread is answered first: an acknowledgment for an acceptance, a release
-- for a refusal, both through the child's own subject executor. If the row
-- update then fails, the thread is already right and the row stays
-- `dispatched`, which no claim redelivers without an idempotency handle -
-- reconciliation resolves it. The reverse order could deliver the same text
-- twice, which is the one outcome this channel must never produce.
local security = require("security")
local bounds = require("bounds")
local gateway = require("gateway")
local inbox_subject = require("inbox_subject")
type Object = {[string]: unknown}
local function fail(code: string, message: string): gateway.Reply
    return {ok = false, error = {code = code, message = message}}
end
-- The delivery a row carries, read before anything is settled.
local function delivery_of(binding: gateway.Binding, message_id: string): (string?, string?, string?)
    local listed = gateway.inbox_queue(binding)
    if not listed.ok then return nil, nil, "the binding's inbox is unavailable" end
    local value = listed.value :: Object?
    local rows = value and value.messages
    if type(rows) ~= "table" then return nil, nil, "the binding's inbox is unavailable" end
    for _, row in ipairs(rows :: {Object}) do
        if tostring(row.message_id) == message_id then
            return tostring(row.delivery_id), tostring(row.status), nil
        end
    end
    return nil, nil, "no inbox row under that id"
end
local function handle(request: unknown): gateway.Reply
    local object = bounds.object(request)
    if not object then return fail("INVALID", "request must be an object") end
    local binding_id = bounds.id(object.binding_id)
    local message_id = bounds.id(object.message_id)
    if not binding_id or not message_id then return fail("INVALID", "binding_id and message_id are identifiers") end
    local outcome = bounds.line(object.outcome, 16)
    if outcome ~= "accepted" and outcome ~= "refused" then return fail("INVALID", "outcome must be accepted or refused") end
    local checked = gateway.check({binding_id = binding_id})
    if not checked.ok then return checked end
    local binding = checked.value :: gateway.Binding
    if not security.can(gateway.ADMIT, binding.action_id) and not security.can(gateway.MANAGE, "bindings") then
        return fail("DENIED", "caller may not settle this binding's inbox")
    end
    local delivery_id, status, lookup_error = delivery_of(binding, message_id)
    if not delivery_id then return fail("NOT_FOUND", lookup_error or "no inbox row under that id") end
    if status ~= "dispatched" and status ~= "claimed" then
        return fail("CONFLICT", "an inbox row is settleable only while claimed or dispatched, not " .. tostring(status))
    end
    local executor, executor_error = inbox_subject.executor(binding)
    if not executor then return fail("UNAVAILABLE", executor_error or "subject executor unavailable") end
    local operation = outcome == "accepted" and inbox_subject.ACK or inbox_subject.RELEASE
    local _, thread_error = inbox_subject.call(executor, operation,
        {thread_id = binding.thread_id, idempotency_key = message_id .. ":" .. outcome, delivery_id = delivery_id})
    if thread_error then return fail("UNAVAILABLE", "the thread refused the settlement: " .. thread_error) end
    return gateway.inbox_settle(request)
end
return {handle = handle}
