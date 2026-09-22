-- MIT. The cross-session inbox boundary: it refuses what it cannot reach,
-- refuses a request it cannot shape, and never reports an outcome the
-- recipient did not give it. Delivery against a live harness is proven
-- separately, with a real child; these are the rules that hold with no
-- recipient at all.
local test = require("test")
local peerinbox = require("peerinbox")
local function define_tests()
    test.describe("Peer inbox boundary", function()
        test.it("refuses a path where no socket exists", function()
            local answer = peerinbox.deliver({socket = "/nonexistent/bee-probe.sock", token = "token", text = "hello"})
            test.eq(answer.accepted, false)
            test.eq(answer.status, "unreachable")
        end)
        test.it("refuses a path that exists and is not a socket", function()
            local answer = peerinbox.deliver({socket = "/etc/hostname", token = "token", text = "hello"})
            test.eq(answer.accepted, false)
            test.eq(answer.status, "unreachable")
            test.eq(answer.detail, "path is not a socket")
        end)
        test.it("refuses a request that names no socket or no text", function()
            -- A missing token is not a malformed request: the adapter resolves
            -- the child's published key itself from the configuration
            -- directory the host assigned it.
            for _, request in ipairs({{token = "t", text = "x"}, {socket = "/tmp/x.sock", token = "t"}}) do
                local answer = peerinbox.deliver(request)
                test.eq(answer.accepted, false)
                test.eq(answer.status, "invalid")
            end
        end)
        test.it("refuses a socket path longer than a Unix socket allows", function()
            local long = "/tmp/" .. string.rep("a", 120) .. ".sock"
            local answer = peerinbox.deliver({socket = long, token = "token", text = "hello"})
            test.eq(answer.status, "invalid")
        end)
        test.it("refuses a body over the inbox bound without opening a connection", function()
            local answer = peerinbox.deliver({socket = "/tmp/bee-probe.sock", token = "token", text = string.rep("x", 32769)})
            test.eq(answer.status, "invalid")
        end)
        test.it("refuses a timeout outside its bounds", function()
            local answer = peerinbox.deliver({socket = "/tmp/bee-probe.sock", token = "token", text = "hello", timeout_ms = 60000})
            test.eq(answer.status, "invalid")
        end)
    end)
end
local cases = test.run_cases(define_tests)
return {run = function(options) return cases(options) end}
