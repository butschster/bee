-- MIT. A standalone projection consumer; its replay cursor is a launch argument.
local process = require("process")
local sql = require("sql")
local client = require("client")
local contract = require("contract")
local security = require("security")
local function main(owner: string, thread: string, after: integer)
    local binding = assert(contract.open("bee.thread_demo:identity_binding"))
    local framing: unknown = binding:inspect()
    assert(type(framing) == "table", "Invalid native contract result")
    local actor = assert(security.actor())
    assert(type(framing.pid) == "string" and framing.pid ~= tostring(process.pid()), "Contract function must have its own execution identity")
    assert(framing.actor == actor:id() and framing.storage_denied == true, "Contract lost caller actor or scope")
    local database, denied = sql.get("bee.thread_demo:db")
    assert(not database and denied, "Subscriber accessed owner storage")
    assert(client.call(owner, "read", thread .. "/foreign", "", "", "", 0).error == "denied")
    assert(client.call(owner, "append", thread, "spoof", "test.run.finished", "{}", 0).error == "denied")
    local cursor = after
    while true do
        local reply = client.call(owner, "wait", thread, "", "", "", cursor)
        assert(reply.error == "", reply.error)
        for _, value in ipairs(reply.rows) do
            if type(value) ~= "table" or type(value.seq) ~= "number" or type(value.kind) ~= "string" or type(value.body) ~= "string" then error("Invalid event") end
            local seq = math.floor(value.seq)
            assert(seq > cursor, "Cursor moved backwards")
            cursor = seq
            assert(process.send(owner, "bee.thread_demo.request", {version = 1, op = "status", thread = thread,
                text = tostring(seq) .. "  " .. value.kind .. "  " .. value.body}))
        end
        local done = client.call(owner, "caught_up", thread, "", "", "", cursor)
        if done.error == "" then break end
        assert(done.error == "pending", done.error)
    end
    assert(process.send(owner, "bee.thread_demo.request", {version = 1, op = "subscriber_done", thread = thread}))
end
return {main = main}
