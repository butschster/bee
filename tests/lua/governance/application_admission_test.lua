-- MIT. Pure governed application-admission value tests.
local test = require("test")
local admission = require("application_admission")

local DIGEST = string.rep("a", 64)

local function record(): {[string]: unknown}
    return {schema_revision = admission.SCHEMA, workspace_id = "workspace-a",
        overlay_owner = "bee.apps:workspace-a", source_node = "node-source",
        source_workspace = "vendor/app", artifact_digest = DIGEST, policy_digest = DIGEST,
        bindings = {
            {definition_id = "vendor.app:second", policies = {"bee:policy-b", "bee:policy-a"},
                thread_access = "observe_post"},
            {definition_id = "vendor.app:first", policies = {}},
        }}
end

local function define_tests()
    test.describe("governed application admission contract", function()
        test.it("normalizes bindings, policies and default thread access", function()
            local measured, measured_error = admission.measure(record())
            if not measured then error(tostring(measured_error)) end
            test.eq(measured.record.bindings[1].definition_id, "vendor.app:first")
            test.eq(measured.record.bindings[1].thread_access, "none")
            test.eq(measured.record.bindings[2].policies[1], "bee:policy-a")
            test.eq(measured.record.bindings[2].thread_access, "observe_post")
            test.is_true(measured.bytes:find('"policies":[]', 1, true) ~= nil)
            test.eq(#measured.digest, 64)
            local repeated = assert(admission.measure(measured.record))
            test.eq(repeated.bytes, measured.bytes)
            test.eq(repeated.digest, measured.digest)
        end)

        test.it("derives one stable reserved identity from the overlay owner", function()
            local first = assert(admission.id("bee.apps:workspace-a"))
            local second = assert(admission.id("bee.apps:workspace-a"))
            local other = assert(admission.id("bee.apps:workspace-b"))
            test.eq(first, second)
            test.is_true(first:sub(1, #admission.RESERVED_PREFIX) == admission.RESERVED_PREFIX)
            test.is_true(first ~= other)
            test.is_nil(admission.id("bad\nowner"))
        end)

        test.it("rejects unknown authority and malformed thread access", function()
            local value = record()
            local rows = value.bindings :: {{[string]: unknown}}
            rows[1].appearance_write = true
            test.is_nil(admission.measure(value))
            rows[1].appearance_write = nil
            rows[1].thread_access = "all"
            test.is_nil(admission.measure(value))
            rows[1].thread_access = "observe_post"
            value.extra = true
            test.is_nil(admission.measure(value))
        end)

        test.it("rejects sparse, duplicate and over-bound selections", function()
            local value = record()
            local rows = value.bindings :: {{[string]: unknown}}
            rows[2] = nil
            rows[3] = {definition_id = "vendor.app:third", policies = {}}
            test.is_nil(admission.measure(value))

            value = record()
            rows = value.bindings :: {{[string]: unknown}}
            rows[2].definition_id = rows[1].definition_id
            test.is_nil(admission.measure(value))

            value = record()
            rows = value.bindings :: {{[string]: unknown}}
            rows[1].policies = {"bee:policy-a", "bee:policy-a"}
            test.is_nil(admission.measure(value))

            local policies: {string} = {}
            for index = 1, admission.MAX_POLICIES + 1 do policies[index] = "bee:policy-" .. tostring(index) end
            rows[1].policies = policies
            test.is_nil(admission.measure(value))
        end)

        test.it("requires exact identity and digest fields", function()
            local value = record()
            value.artifact_digest = "short"
            test.is_nil(admission.measure(value))
            value = record()
            value.schema_revision = "bee.governance-application-admission@2"
            test.is_nil(admission.measure(value))
            value = record()
            value.overlay_owner = "bad\nowner"
            test.is_nil(admission.measure(value))
        end)
    end)
end

return test.run_cases(define_tests)
