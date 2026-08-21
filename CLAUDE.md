# transcriptor - Agent Working Agreement

These rules are binding.
They override default behavior and general habits.
When a rule here conflicts with something you want to do, the rule wins.

## The prime rule

One task at a time.
One idea per pull request.
Every PR must be small enough that a human reads the whole diff in one sitting and holds all of it in their head at once.

If you cannot describe a PR in a single sentence without using "and", it is two PRs.

## Task sizing

A task is one testable behavior change.
Examples of correctly sized tasks: "cache extracted audio between runs", "add a `--language` flag to the transcribe command", "retry the map stage on transient model errors".

Sizing limits:

- A task must be deliverable in 5 or fewer implementation PRs.
- If it needs more, it is two tasks. Split it and pick one.
- A task that touches more than one subsystem is usually two tasks.

## The workflow

Every task runs through these phases in order.
Do not skip a phase.
Do not start a phase before the previous one is approved.

### Tooling exception

Changes with no testable behavior in the package skip Phases 1 through 3.
This covers the Makefile, CI configuration, editor configuration, and documentation.

Such a change ships as a single PR into `main` that states every command the author ran and the result of each.
Verification is running the thing, not asserting on it.

The exception never applies to anything under `Sources/`.
If a change touches both, split it: the tooling part takes the exception, the source part takes the full workflow.

### Phase 0 - Research

Read the relevant code before writing anything.

Produce three things:

1. A one-sentence statement of the task.
2. A list of the behaviors that need tests, each one a sentence.
3. A list of the implementation slices, each one a future PR.

Write all three to `.claude/tasks/<slug>.md` using the handoff format below.

No production code.
No test code.
Stop and wait for the human to approve the task statement and the test list.

### Phase 1 - Tests PR

Branch from `main` to `feature/<slug>`.
Push `feature/<slug>` so it exists on the remote.
Branch from `feature/<slug>` to `<slug>/tests`.

Write only tests.
Add the minimum stubs needed to compile: empty types, empty function bodies, `fatalError("not implemented")`.
Stubs carry no logic.
If you find yourself writing behavior in a stub, stop.

The tests must fail for the right reason.
Run them and confirm they fail because the behavior is missing, not because of a typo or a compile error you overlooked.

Open a PR from `<slug>/tests` into `feature/<slug>`.
Stop and wait for approval.

### Phase 2 - Context clear

After the tests PR merges, update `.claude/tasks/<slug>.md` with the merged PR link.

Then print exactly this and nothing after it:

> Tests merged. Please `/clear` now, then say "resume <slug>".

Do not begin implementing.
Do not summarize what you are about to do.
Stop.

Implementation always starts from a fresh context reading the handoff file.
A stale context carries assumptions the tests do not, and those assumptions leak into the implementation.

### Phase 3 - Implementation slices

First action after the clear: read `.claude/tasks/<slug>.md`.
Then read the tests that were merged.
The tests are the specification. The handoff file is the map.

For each slice, in order:

1. Branch from `feature/<slug>` to `<slug>/<slice-name>`.
2. Write the minimum code that turns the named tests green.
3. Confirm those tests pass and no previously passing test broke.
4. Open a PR into `feature/<slug>`, naming which tests it turns green.
5. Update the handoff file.
6. Stop and wait for the human to say go.

Do not start the next slice before that go-ahead.

### Phase 4 - Integration

When every test is green on `feature/<slug>`, open a PR from `feature/<slug>` into `main`.
This PR must be fully green.
Squash merge.
Delete the branch.
Move `.claude/tasks/<slug>.md` to `.claude/tasks/done/`.

## Branch and PR conventions

```
main
 └─ feature/<slug>              integration branch, never merged into directly except by slice PRs
     ├─ <slug>/tests            tests only
     ├─ <slug>/<slice-name>     one implementation slice
     └─ <slug>/<slice-name>     one implementation slice
```

Only the `feature/<slug>` to `main` PR must be green.
Slice PRs may leave some tests still failing, as long as they say which ones and why.

Every PR description states:

- The one sentence this PR does.
- Which tests it makes green, by name.
- Which tests are still expected to fail, by name.

## PR size limits

- Target: under 200 changed lines.
- Ceiling: 400 changed lines, excluding lockfiles and generated code.

Over the ceiling means split the PR.
It does not mean write a longer justification.

If a slice grows past the ceiling mid-work, stop, split what you have, and say so.

### Tool-generated changes

A change produced entirely by running a tool, such as a formatter, is exempt from the ceiling.
Splitting it buys nothing, because nobody reviews it line by line.

Such a PR must say which command produced it, and must change nothing by hand.
If a hand edit is needed, it goes in a separate PR, before or after, never mixed in.
Verification is that the build and the full test suite still pass.

## Staying on task

You will notice unrelated problems while working.
Do not fix them.

Fix an unrelated problem only when it blocks this PR from being green.
Otherwise add it to the `## Follow-ups` section of the handoff file, mention it in one line to the human, and continue the task at hand.

This narrows the global "fix problems you see" rule for this repository.
The reason is that unrelated fixes are what turn a 150 line PR into a 600 line PR that nobody reviews properly.
Follow-ups get their own task later.

Never in scope unless the task is explicitly about it:

- Renaming things you did not otherwise touch.
- Reformatting untouched code.
- Refactoring adjacent code that already works.
- Upgrading dependencies.
- Improving unrelated test coverage.

## Handoff file format

`.claude/tasks/<slug>.md`:

```markdown
# <slug>

## Task
<one sentence>

## Tests
- [ ] <behavior> - `<testFunctionName>`
- [ ] <behavior> - `<testFunctionName>`

## Slices
- [ ] 1. <slice name> - turns green: <test names>
- [ ] 2. <slice name> - turns green: <test names>

## PRs
- tests: <url>
- slice 1: <url>

## Follow-ups
- <unrelated problem noticed, not fixed>

## Notes
<decisions made during research that the tests do not capture>
```

Keep it current.
It is the only thing that survives a context clear.

## Project commands

Swift package, tools version 6.3, macOS 26 minimum.
Tests use the `Testing` framework (`@Test`, `#expect`), not XCTest.

```
make build                       # swift build
make release                     # swift build -c release
make test                        # swift test
make run ARGS="videos/x.mp4"     # swift run transcriptor
make format                      # swiftformat, writes in place
make lint                        # swiftformat --lint plus swiftlint
make clean                       # swift package clean
make                             # lists the targets
```

Use the make targets rather than the underlying `swift` commands, so the two cannot drift apart.
The one exception is running a single test, which has no target:

```
swift test --filter <testFunctionName>
```

Package targets: `TranscriptorKit` (library), `transcriptor` (CLI), `TranscriptorKitTests`.

## GitHub

Use `npx -y gh-axi <command>` for all PR, issue, and CI operations.
Do not use the `gh` CLI or the GitHub MCP server directly.

Commit messages carry no agent attribution and no co-author trailer.

## Red flags

These thoughts mean stop.
Each one is a rationalization with a known outcome.

| Thought | Reality |
|---------|---------|
| "It is all one feature, so it is one PR" | Features are not PR sized. Behaviors are. Split it. |
| "Splitting this is more work than just doing it" | The reviewer pays that cost instead, with interest. Split it. |
| "The test change is trivial, I will fold it into the implementation PR" | Tests come first, in their own PR. That is the whole point. |
| "I already have the context loaded, clearing wastes it" | The stale context is the problem, not the cost. Clear it. |
| "This lint error is right there, I will just fix it" | Unless it blocks green, it is a follow-up. |
| "I will write the implementation while I am in the test file" | Phase 1 is tests only. Stubs carry no logic. |
| "The human will probably approve, I will start now" | Every phase gate is a hard stop. Wait for the words. |
| "I can do the next slice too, it is small" | One slice, one PR, one approval. Stop after each. |
| "The task grew, but I am almost done" | A task that grew past 5 slices was two tasks. Stop and say so. |
| "I do not need the handoff file, I remember" | You will not, after the clear. Write it. |
| "This is basically tooling, the exception covers it" | The exception is for code with no testable behavior. Anything in `Sources/` never qualifies. |
