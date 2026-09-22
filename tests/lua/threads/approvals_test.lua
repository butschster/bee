-- MIT. The approval ingress: only the approval authority appends, records
-- key on the owner's event id, a replay returns the same record, a
-- different body under a used key conflicts, and no decision is committed
-- by the thread. Its notices owe their recipient a delivery and never an
-- answer.
local test = require("test")
local harness = require("harness")
local AUTHORITY = {"bee:thread_create_policy", "bee:thread_observe_policy", "bee:thread_lifecycle_policy", "bee:thread_approval_policy"}
local function request_body(approval_id: string): {[string]: unknown}
    return {approval_id = approval_id, request_kind = "permission", requester_id = "bee.test.requester", operation_ref = "bee.hive.telemetry:stats",
        prompt = {text = "Allow stats?"}, response_schema = {type = "object", additionalProperties = false, properties = {option = {type = "string"}}},
        expires_at = "2026-09-10T00:00:00.000Z", state = "pending"}
end
local function define_tests()
    test.describe("Thread approval ingress", function()
        local authority = harness.principal("approvals-owner", AUTHORITY)
        local member = harness.principal("member", harness.ALL)
        test.it("appends typed approval projections under the owner's event id and replays them", function()
            local thread_id = harness.thread(authority, "Approvals")
            harness.value(authority:call("join", {thread_id = thread_id, idempotency_key = harness.key(), member_id = "member", role = "participant", expected_revision = 1}))
            local first = harness.value(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e1",
                kind = "approval.request", body = request_body("ap-1")}))
            test.eq(first.sequence, 1)
            local replay = harness.value(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e1",
                kind = "approval.request", body = request_body("ap-1")}))
            test.eq(replay.record_id, first.record_id)
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e1",
                kind = "approval.request", body = request_body("ap-2")})), "CONFLICT")
            local decided = harness.value(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e2",
                kind = "approval.transition", body = {approval_id = "ap-1", expected_revision = 1, state = "approved", decider_id = "bee.test.approver", response = {text = "yes"}, reason = "approved by the owner"}}))
            test.eq(decided.sequence, 2)
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e3",
                kind = "approval.transition", body = {approval_id = "ap-1", expected_revision = 1, state = "settled", reason = "no"}})), "INVALID_ARGUMENT")
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e4",
                kind = "receipt", body = {scope = "action", outcome = "succeeded", evidence_refs = {}}})), "INVALID_ARGUMENT")
            test.eq(harness.code(member:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "e5",
                kind = "approval.request", body = request_body("ap-3")})), "DENIED")
            local page = harness.value(member:call("read_after", {thread_id = thread_id, cursor = 0, filter = {kinds = {"approval.request", "approval.transition"}}}))
            test.eq(#page.records, 2)
            test.eq(page.records[1].source, "bee")
            test.eq(page.records[1].body.request_kind, "permission")
            test.eq(page.records[2].body.state, "approved")
            test.eq(page.records[2].body.decider_id, "bee.test.approver")
        end)
        test.it("addresses a notice to a member and owes the delivery exactly once", function()
            local thread_id = harness.thread(authority, "Approvals")
            harness.value(authority:call("join", {thread_id = thread_id, idempotency_key = harness.key(), member_id = "member", role = "participant", expected_revision = 1}))
            local notice: {[string]: unknown} = {message_id = "ap-9:2:notice", message_kind = "notification", recipient_ids = {"member"},
                content = {text = "Approval ap-9 is approved."}}
            local first = harness.value(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n1",
                kind = "message", body = notice}))
            local replay = harness.value(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n1",
                kind = "message", body = notice}))
            test.eq(replay.record_id, first.record_id)
            local page = harness.value(member:call("read_after", {thread_id = thread_id, cursor = 0, filter = {kinds = {"message"}}}))
            test.eq(#page.records, 1)
            test.eq(page.records[1].body.sender_id, "approvals-owner")
            -- A replayed projection commits nothing, so the recipient still
            -- owes exactly one delivery for it.
            local claimed = harness.value(member:call("claim", {thread_id = thread_id, idempotency_key = harness.key(), consumer_id = "inbox", limit = 4}))
            test.eq(#claimed.deliveries, 1)
            test.eq(claimed.deliveries[1].message_id, "ap-9:2:notice")
            -- Nothing appended here may owe an answer: this ingress holds no
            -- membership, so nobody could ever be held to one.
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n2", kind = "message",
                body = {message_id = "ap-9:3", message_kind = "request", recipient_ids = {"member"}, content = {text = "Answer me."}}})), "INVALID_ARGUMENT")
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n3", kind = "message",
                body = {message_id = "ap-9:4:notice", message_kind = "notification", recipient_ids = {}, content = {text = "To nobody."}}})), "INVALID_ARGUMENT")
            test.eq(harness.code(authority:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n4", kind = "message",
                body = {message_id = "ap-9:5:notice", message_kind = "notification", sender_id = "member", recipient_ids = {"member"}, content = {text = "Not mine."}}})), "INVALID_ARGUMENT")
            test.eq(harness.code(member:call("approval_append", {thread_id = thread_id, idempotency_key = harness.key(), owner_event_id = "n5",
                kind = "message", body = notice})), "DENIED")
        end)
    end)
end
return test.run_cases(define_tests)
