-- MIT. Private fixture RPC; not a public Bee API.
local process = require("process")
local channel = require("channel")
local time = require("time")
type Reply = {seq: integer, rows: {unknown}, error: string}
local M = {}
function M.call(owner: string, op: string, thread: string, key: string, kind: string, body: string, after: integer): Reply
    local replies = assert(process.listen("bee.thread_demo.reply", {message = true}))
    local timeout = assert(time.timer("3s"))
    assert(process.send(owner, "bee.thread_demo.request", {version = 1, op = op, thread = thread, key = key, kind = kind, body = body, after = after}))
    local result: Reply = {seq = 0, rows = {}, error = "timeout"}
    while true do
        local selected = channel.select({replies:case_receive(), timeout:channel():case_receive()})
        if not selected.ok or selected.channel ~= replies then break end
        if selected.value:from() == owner then
            local data: unknown = selected.value:payload():data()
            if type(data) == "table" and data.version == 1 and type(data.seq) == "number" and type(data.rows) == "table" and type(data.error) == "string" then
                local rows: {unknown} = {}
                for key, value in pairs(data.rows) do
                    if type(key) ~= "number" or key < 1 or key > 64 or key ~= math.floor(key) then error("Invalid event page") end
                    rows[math.floor(key)] = value
                end
                result = {seq = math.floor(data.seq), rows = rows, error = data.error}
                break
            end
        end
    end
    timeout:stop(); process.unlisten(replies)
    return result
end
return M
