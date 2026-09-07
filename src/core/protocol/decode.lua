local model = require("model")
local appearance = require("appearance")
local M = {}
type Reply = {request_id: string, op: string, id: string, instance_id: string, title: string, mount: string, error: string}
function M.reply(value: unknown): Reply?
    if type(value) ~= "table" then return nil end
    if type(value.request_id) ~= "string" or type(value.op) ~= "string" or type(value.id) ~= "string"
        or type(value.instance_id) ~= "string" or type(value.title) ~= "string"
        or type(value.mount) ~= "string" or type(value.error) ~= "string" then return nil end
    return {request_id = value.request_id, op = value.op, id = value.id, instance_id = value.instance_id,
        title = value.title, mount = value.mount, error = value.error}
end
local function integer(value: unknown): integer?
    if type(value) ~= "number" or value ~= value or value < -2147483647 or value > 2147483647 then return nil end
    if value ~= math.floor(value) then return nil end
    return math.floor(value)
end
local function rect(value: unknown): model.Rect?
    if type(value) ~= "table" then return nil end
    local x, y, width, height = integer(value.x), integer(value.y), integer(value.width), integer(value.height)
    if not x or not y or not width or not height or width < 1 or height < 1 then return nil end
    return {x = x, y = y, width = width, height = height}
end
local function window(value: unknown): model.Window?
    if type(value) ~= "table" then return nil end
    if type(value.id) ~= "string" or type(value.instance_id) ~= "string" or type(value.title) ~= "string" then return nil end
    local bounds, normal = rect(value.bounds), rect(value.normal_bounds)
    if not bounds or not normal then return nil end
    local mode = value.mode
    if mode ~= "floating" and mode ~= "fullscreen" and mode ~= "minimized" and mode ~= "collapsed" then return nil end
    local restore = value.restore_mode
    if restore ~= "floating" and restore ~= "fullscreen" and restore ~= "collapsed" then return nil end
    return {id = value.id, instance_id = value.instance_id, title = value.title,
        bounds = bounds, normal_bounds = normal, mode = mode, restore_mode = restore}
end
function M.scene(value: unknown): model.Scene?
    if type(value) ~= "table" or type(value.windows) ~= "table" or type(value.focus) ~= "string" then return nil end
    local width, height, revision = integer(value.width), integer(value.height), integer(value.revision)
    if not width or not height or not revision or width < 1 or height < 1 or revision < 0 then return nil end
    local count = 0
    for key in pairs(value.windows) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 16 then return nil end
        count = count + 1
    end
    local windows: {model.Window} = {}
    local ids: {[string]: boolean} = {}
    for index = 1, count do
        local item = window(value.windows[index])
        if not item or item.id == "" or ids[item.id] then return nil end
        if item.id == value.focus and item.mode == "minimized" then return nil end
        ids[item.id] = true
        windows[#windows + 1] = item
    end
    if value.focus ~= "" and not ids[value.focus] then return nil end
    return {width = width, height = height, revision = revision, focus = value.focus, windows = windows}
end
type Acknowledgement = {request_id: string, scene: model.Scene}
function M.ack(value: unknown): Acknowledgement?
    if type(value) ~= "table" or type(value.request_id) ~= "string" or #value.request_id > 80 then return nil end
    local scene = M.scene(value.scene)
    if not scene then return nil end
    return {request_id = value.request_id, scene = scene}
end
type Desktop = {scene: model.Scene, tabs: {string}, preferences: appearance.Preferences}
function M.desktop(value: unknown): Desktop?
    if type(value) ~= "table" or type(value.tabs) ~= "table" then return nil end
    local scene = M.scene(value.scene)
    if not scene then return nil end
    local count = 0
    for key in pairs(value.tabs) do
        if type(key) ~= "number" or key ~= math.floor(key) or key < 1 or key > 16 then return nil end
        count = count + 1
    end
    if count ~= #scene.windows then return nil end
    local known: {[string]: boolean} = {}
    for _, win in ipairs(scene.windows) do known[win.id] = true end
    local tabs: {string} = {}
    for index = 1, count do
        local id = value.tabs[index]
        if type(id) ~= "string" or not known[id] then return nil end
        known[id] = nil
        tabs[#tabs + 1] = id
    end
    local preferences = value.preferences == nil and appearance.defaults() or appearance.decode(value.preferences)
    if not preferences then return nil end
    return {scene = scene, tabs = tabs, preferences = preferences}
end
return M
