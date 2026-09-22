-- MIT. The inbox's own thread operations, run as the bound subject.
--
-- Obligations belong to the child and claims are self-service, so nothing
-- here impersonates anyone: the gateway builds the same subject executor its
-- tools run under, and the child's own actor claims, acknowledges and
-- releases what the child owes. The thread owner authorizes again in every
-- case; this library adds no authority of its own and writes no record.
local funcs = require("funcs")
local security = require("security")
local context = require("context")
local gateway = require("gateway")
local M = {}
type Object = {[string]: unknown}
M.SCOPE = "bee:gateway_inbox_subject_policy"
M.CLAIM = "bee.threads.delivery:claim"
M.ACK = "bee.threads.delivery:ack"
M.RELEASE = "bee.threads.delivery:release"
M.READ = "bee.threads.service:read_after"
-- The executor a binding's own subject runs under. Its shape follows the MCP
-- endpoint's: context first, then the actor, then the host-named scope.
function M.executor(binding: gateway.Binding): (funcs.Executor?, string?)
    local policy, policy_error = security.policy(M.SCOPE)
    if policy_error or not policy then return nil, "policy " .. M.SCOPE .. " unavailable" end
    local subject, subject_error = security.new_actor(binding.subject)
    if not subject then return nil, tostring(subject_error) end
    local attributed, attribution_error = context.bind(nil, {binding_id = binding.binding_id, thread_id = binding.thread_id,
        subject = binding.subject, action_id = binding.action_id, attempt_id = binding.attempt_id,
        policy_ref = binding.policy_ref, workspace_id = binding.workspace_id, origin_view = binding.origin_view})
    if not attributed then return nil, tostring(attribution_error) end
    local executor, context_error = funcs.new():with_context(attributed)
    if not executor then return nil, tostring(context_error) end
    local acted, actor_error = executor:with_actor(subject)
    if not acted then return nil, tostring(actor_error) end
    local scoped, scope_error = acted:with_scope(security.new_scope({policy}))
    if not scoped then return nil, tostring(scope_error) end
    return scoped, nil
end
-- One owner call, with the reply unwrapped to the shape the thread owner
-- answers with. A transport failure and a refusal are told apart: the first
-- is unavailability, the second is the owner's decision.
function M.call(executor: funcs.Executor, operation: string, request: Object): (Object?, string?)
    local reply, call_error = executor:call(operation, request)
    if call_error then return nil, tostring(call_error) end
    local object = reply :: Object?
    if type(object) ~= "table" then return nil, operation .. ": the owner answered nothing" end
    if object.ok == false then
        local fault = object.error
        local detail = type(fault) == "table" and tostring((fault :: Object).message or (fault :: Object).code) or "refused"
        return nil, operation .. ": " .. detail
    end
    local value = object.value
    if type(value) == "table" then return value :: Object, nil end
    return {}, nil
end
return M
