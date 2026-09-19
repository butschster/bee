local test = require("test")
local protocol = require("protocol")
local contract = require("contract")

local function define_tests()
    test.describe("Agent application open protocol", function()
        test.it("accepts only the bound workspace and bounded literal arguments", function()
            local workspace = string.rep("a", 32)
            local request = protocol.request({version = 1, workspace_id = workspace, request_id = "open-1",
                definition_id = "bee.example:app", arguments = {"one", "two"}}, workspace)
            if not request then error("valid open request rejected") end
            test.eq(request.definition_id, "bee.example:app")
            test.eq(request.arguments[2], "two")
            test.is_nil(protocol.request({version = 1, workspace_id = string.rep("b", 32), request_id = "open-1",
                definition_id = "bee.example:app", arguments = {}}, workspace))
            test.is_nil(protocol.request({version = 1, workspace_id = workspace, request_id = "open-1",
                definition_id = "bee.example:app", arguments = {}, extra = true}, workspace))
            test.is_nil(protocol.request({version = 1, workspace_id = workspace, request_id = "open-1",
                definition_id = "bee.example:app", arguments = {string.rep("x", 1025)}}, workspace))
        end)
        test.it("validates the forwarded broker reply against both identities", function()
            local workspace = string.rep("a", 32)
            local reply = contract.reply("open-1", "open")
            reply.workspace_id = workspace
            local wrapped = protocol.reply({version = 1, workspace_id = workspace, request_id = "open-1", reply = reply}, workspace)
            if not wrapped then error("valid open reply rejected") end
            test.eq(wrapped.request_id, "open-1")
            test.eq(wrapped.reply.op, "open")
            test.is_nil(protocol.reply({version = 1, workspace_id = workspace, request_id = "other", reply = reply}, workspace))
            test.is_nil(protocol.reply({version = 1, workspace_id = string.rep("b", 32), request_id = "open-1", reply = reply}, workspace))
        end)
    end)
end

return require("test").run_cases(define_tests)
