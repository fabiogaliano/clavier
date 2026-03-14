# AI Agent Prompts

Use these prompts exactly to keep implementation work bounded.

## Universal Rules For Every Session

- Work on **one workstream only**.
- Read `docs/implementation-plan/README.md` first.
- Read this file second.
- Read exactly one workstream doc third.
- Read only the code files listed in that workstream doc.
- Do not inspect or modify files outside that allowed file list.
- If another file becomes necessary, stop and update the plan docs before touching code.
- Update status and logs when the session ends.

## Start Prompt Template

```text
You are implementing one bounded workstream for keynave.

Mandatory read order:
1. Read `docs/implementation-plan/README.md`
2. Read `docs/implementation-plan/agent-prompts.md`
3. Read `docs/implementation-plan/workstreams/[WORKSTREAM_FILE].md`
4. Read only the allowed source files listed in that workstream doc

Hard constraints:
- Work on `[WORKSTREAM_ID]` only
- Do not inspect unrelated files
- Do not edit files outside the allowed list
- If you discover extra files are needed, stop and update the plan docs first
- Keep the session focused on finishing checklist items for this workstream only
- Update the workstream status to `in-progress` when starting
- Update the main plan log and the workstream log before ending the session

Goal for this session:
- Complete the next unchecked items in `[WORKSTREAM_ID]`
- Keep changes minimal and localized
- Verify only against the acceptance criteria for `[WORKSTREAM_ID]`

Deliverable at the end of the session:
- Code changes limited to the allowed files
- Updated checklist state
- Updated status in the main plan and the workstream doc
- Short log entry describing what was done and what remains
```

## Resume Prompt Template

```text
Resume work on keynave implementation workstream `[WORKSTREAM_ID]`.

Mandatory read order:
1. Read `docs/implementation-plan/README.md`
2. Read `docs/implementation-plan/agent-prompts.md`
3. Read `docs/implementation-plan/workstreams/[WORKSTREAM_FILE].md`
4. Read only the allowed source files listed in that workstream doc
5. Read the main log and the workstream log to understand the latest state

Hard constraints:
- Stay inside `[WORKSTREAM_ID]`
- Do not start another workstream
- Do not widen scope without updating the plan docs first
- If blocked, mark the workstream `blocked` and record the exact blocker

Goal for this session:
- Continue from the first unchecked task in `[WORKSTREAM_ID]`
- Finish as many remaining checklist items as possible without leaving scope
- Re-verify the acceptance criteria touched by this session

Deliverable at the end of the session:
- Updated code in the allowed files only
- Updated checklist state
- Updated logs
- Updated status in both the main plan and the workstream doc
```

## Ready-To-Use Prompt For The First Session

```text
You are starting the first keynave implementation session.

Mandatory read order:
1. Read `docs/implementation-plan/README.md`
2. Read `docs/implementation-plan/agent-prompts.md`
3. Read `docs/implementation-plan/workstreams/01-coordinate-foundation.md`
4. Read only the allowed source files listed in that workstream doc

Hard constraints:
- Work on `WS-01` only
- Do not inspect or edit files outside the `WS-01` allowed file list
- Do not mix in hint placement, clickability, settings, or hotkey refactors yet
- If another file is required, stop and update the plan docs first

Goal for this session:
- Establish the shared coordinate foundation for multi-display correctness
- Keep changes minimal and localized
- Update statuses and logs before ending the session
```

## Session-End Checklist

- [ ] Status updated in `docs/implementation-plan/README.md`
- [ ] Status updated in the current workstream doc
- [ ] Main log updated
- [ ] Workstream log updated
- [ ] Any scope expansion recorded explicitly before code changes
- [ ] Remaining tasks left unchecked
