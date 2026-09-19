# Agent applications release sequence — September 19

The destination is a usable Bee where managed agents, external workers, local
models and deterministic tools coordinate through profiles, scoped MCP, durable
threads and governed applications. Prove applications before adding more worker
types. `llm.transition` is a future component integration, not a current API.

Work one acceptance milestone at a time:

1. **Application opening — active.** Complete the explicitly admitted MCP
   operation through the production gateway, workspace host and broker. Prove
   sender authorization, binding-selected workspace, refusal before application
   admission, concurrent retry/conflict handling, bounded pending state, visible
   client inventory and restart recovery in source and packed runs. Protocol
   tests alone do not establish completion. Local commit `edbdbf2` is a draft
   implementation awaiting these checks; it is not a release.
2. **Executable integration and global candidate.** After runtime PR #787 lands,
   integrate the prepared Bee Host/Plan port and update the runtime/build inputs.
   Run assembled native, offline startup, project isolation, recovery and pack
   isolation gates. Install only the verified candidate, retaining rollback.
3. **Agent identity in the UI.** Display definition and saved-profile identities
   and descriptions when selecting an agent. Retain the selected launch identity
   in durable records so the thread can show it after restart. Keep definition,
   saved profile, driver profile, action, attempt and thread identities distinct.
4. **Promptmap quality audit.** Scan components for duplicate ownership, unused
   code and unnecessary indirection. Verify findings, fix bounded groups and run
   their behavioral gates. Do not create speculative abstractions from scan
   suggestions.
5. **Reference application.** Prove one complete agent-authored application
   before adding further hybrid worker/model features.

Completed prerequisite: Bee PR #14 merged to `main` at `d97fd77`, with offline
docs, delivery, scoped child launch and Timeline fixes. Its recorded local suite
passed 1,106 tests; hosted jobs could not start because of GitHub billing.
Runtime PR #787 at `7f9e7e89bc` passes all hosted checks, including Windows after
the cache-repair fix, and is assigned to Rodrigo (`skhaz`) for review.

The global executable has not been updated by this sequence. Preserve the
unrelated `modules/bee-registry-planner/` work.
