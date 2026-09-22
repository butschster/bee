-- MIT. Gateway method inbox_dispatched: the caller's actor, the linked store, one inbox operation.
local gateway = require("gateway")
local function handle(request: unknown): gateway.Reply
    return gateway.inbox_dispatched(request)
end
return {handle = handle}
