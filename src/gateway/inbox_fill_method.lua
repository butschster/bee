-- MIT. Gateway method inbox_fill: turn what a child owes into queue rows.
--
-- The child's own actor claims its own obligations, through the same subject
-- executor its tools run under, so nothing delegates and nothing impersonates.
-- Filling is not delivery: a row lands `queued` and the thread delivery stays
-- claimed until a carrier dispatches it and the harness answers.
local security = require("security")
local funcs = require("funcs")
local uuid = require("uuid")
local bounds = require("bounds")
local gateway = require("gateway")
local subject = require("inbox_subject")
type Object = {[string]: unknown}
local MAX_FILL = 16
local function fail(code: string, message: string): gateway.Reply
    return {ok = false, error = {code = code, message = message}}
end
-- The text a harness will receive. A record the owner will not hand back is
-- skipped rather than delivered as a guess.
local function body_of(executor: funcs.Executor, thread_id: string, sequence: integer, record_id: string): (Object?, string?)
    local page, read_error = subject.call(executor, subject.READ, {thread_id = thread_id, cursor = sequence - 1, limit = 1})
    if not page then return nil, read_error end
    local records = page.records
    if type(records) ~= "table" then return nil, "the owner returned no records" end
    for _, entry in ipairs(records :: {Object}) do
        if tostring(entry.record_id) == record_id then
            local content = entry.content
            local text: string? = nil
            if type(content) == "table" then text = (content :: Object).text :: string? end
            if type(text) ~= "string" or text == "" then return nil, "the record carries no deliverable text" end
            return {text = text, record_id = record_id, sequence = sequence, kind = entry.kind, sender = entry.sender_id}, nil
        end
    end
    return nil, "the record is not in the owner's page"
end
local function handle(request: unknown): gateway.Reply
    local object = bounds.object(request)
    if not object then return fail("INVALID", "request must be an object") end
    local unknown_field = bounds.fields(object, {"binding_id", "carrier_epoch", "limit"})
    if unknown_field then return fail("INVALID", unknown_field) end
    local binding_id = bounds.id(object.binding_id)
    if not binding_id then return fail("INVALID", "binding_id is not an identifier") end
    local carrier_epoch = bounds.integer(object.carrier_epoch)
    if not carrier_epoch or carrier_epoch < 1 then return fail("INVALID", "carrier_epoch must be a positive integer") end
    local limit = MAX_FILL
    if object.limit ~= nil then
        local declared = bounds.integer(object.limit)
        if not declared or declared < 1 or declared > MAX_FILL then return fail("INVALID", "limit must be between 1 and " .. tostring(MAX_FILL)) end
        limit = declared
    end
    local checked = gateway.check({binding_id = binding_id})
    if not checked.ok then return checked end
    local binding = checked.value :: gateway.Binding
    if not security.can(gateway.ADMIT, binding.action_id) and not security.can(gateway.MANAGE, "bindings") then
        return fail("DENIED", "caller may not fill this binding's inbox")
    end
    local executor, executor_error = subject.executor(binding)
    if not executor then return fail("UNAVAILABLE", executor_error or "subject executor unavailable") end
    local key, key_error = uuid.v7()
    if key_error or not key then return fail("INTERNAL", "mint claim key") end
    local claimed, claim_error = subject.call(executor, subject.CLAIM,
        {thread_id = binding.thread_id, idempotency_key = key, consumer_id = "inbox", channel = "queue", limit = limit})
    if not claimed then return fail("UNAVAILABLE", claim_error or "claim failed") end
    local deliveries = claimed.deliveries
    if type(deliveries) ~= "table" then return {ok = true, value = {binding_id = binding_id, enqueued = 0, released = 0}} end
    local enqueued, released = 0, 0
    for _, delivery in ipairs(deliveries :: {Object}) do
        local delivery_id = bounds.id(delivery.delivery_id)
        local message_id = bounds.id(delivery.message_id)
        local record_id = bounds.id(delivery.record_id)
        local sequence = bounds.integer(delivery.sequence)
        local body: Object? = nil
        local body_error: string? = nil
        if delivery_id and message_id and record_id and sequence then
            body, body_error = body_of(executor, binding.thread_id, sequence, record_id)
        else
            body_error = "the claim is missing its identifiers"
        end
        local stored = false
        if body and delivery_id and message_id and record_id and sequence then
            local reply = gateway.inbox_enqueue({binding_id = binding_id, carrier_epoch = carrier_epoch, delivery_id = delivery_id,
                thread_message_id = message_id, record_id = record_id, record_sequence = sequence, body = body})
            if reply.ok then stored = true; enqueued = enqueued + 1 end
        end
        -- Backpressure and unreadable records return the obligation to the
        -- thread instead of dropping it: the queue is bounded, the thread is
        -- the record, and an unclaimed obligation is visible there.
        if not stored and delivery_id then
            local _, release_error = subject.call(executor, subject.RELEASE, {thread_id = binding.thread_id,
                idempotency_key = tostring(key) .. ":" .. delivery_id, delivery_id = delivery_id})
            if not release_error then released = released + 1 end
        end
    end
    return {ok = true, value = {binding_id = binding_id, enqueued = enqueued, released = released}}
end
return {handle = handle}
