local process = require("process")
local channel = require("channel")
local model = require("model")

-- Only the attachment owner can mutate this private desktop session.
-- No application launch, terminal lease, or opaque handle enters its state.
local function main(owner: string, width: integer, height: integer)
    local commands = assert(process.listen("bee.desktop.command", {message = true}))
    local lifecycle = assert(process.events())
    assert(process.monitor(owner))
    local scene = model.new(width, height)
    assert(process.send(owner, "bee.desktop.scene", scene))
    while true do
        local selected = channel.select({commands:case_receive(), lifecycle:case_receive()})
        if not selected.ok then break end
        if selected.channel == lifecycle then
            if selected.value.kind == process.event.CANCEL then break end
            if selected.value.kind == process.event.EXIT and tostring(selected.value.from) == owner then break end
        else
            local msg = selected.value
            if msg:from() == owner then
                local data: unknown = msg:payload():data()
                if type(data) == "table" and type(data.op) == "string" then
                    if data.op == "shutdown" then break end
                    local before = scene
                    if data.op == "screen" and type(data.width) == "number" and type(data.height) == "number" then
                        scene = model.resize_screen(scene, math.floor(data.width), math.floor(data.height))
                    elseif type(data.id) == "string" then
                        if data.op == "add" and type(data.instance_id) == "string" and type(data.title) == "string" then
                            scene = model.add(scene, data.id, data.instance_id, data.title)
                        elseif data.op == "focus" then scene = model.focus(scene, data.id)
                        elseif data.op == "fullscreen" then scene = model.toggle_fullscreen(scene, data.id)
                        elseif data.op == "minimize" then scene = model.minimize(scene, data.id)
                        elseif data.op == "collapse" then scene = model.collapse(scene, data.id)
                        elseif data.op == "restore" then scene = model.restore(scene, data.id)
                        elseif data.op == "snap" and type(data.side) == "string" then
                            scene = model.snap(scene, data.id, data.side)
                        elseif data.op == "remove" then scene = model.remove(scene, data.id)
                        elseif data.op == "place" and type(data.x) == "number" and type(data.y) == "number"
                            and type(data.width) == "number" and type(data.height) == "number" then
                            scene = model.place(scene, data.id, {x = math.floor(data.x), y = math.floor(data.y),
                                width = math.floor(data.width), height = math.floor(data.height)})
                        end
                    end
                    if scene ~= before or data.op == "snapshot" or data.op == "place" then process.send(owner, "bee.desktop.scene", scene) end
                    -- No-op commands also acknowledge the caller's input intent.
                    if type(data.request_id) == "string" and #data.request_id <= 80 then
                        process.send(owner, "bee.desktop.ack", {request_id = data.request_id, scene = scene})
                    end
                end
            end
        end
    end
    process.unlisten(commands)
end
return {main = main}
