# Plan 001: Add a GitHub Actions workflow that builds and runs unit tests on every push

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 4392be3..HEAD -- .github/workflows/ CLAUDE.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" facts against the live repo before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S–M
- **Risk**: LOW (additive — no app code changes)
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `4392be3`, 2026-06-11

## Why this matters

This repo is a 438-file iOS app maintained by a solo developer who commits directly to `main`. There is currently **no CI that builds or tests anything** — the only workflow deploys GitHub Pages. The project's own CLAUDE.md documents that a single broken test file fails the entire test target even with `-only-testing:` filters, and that several past regressions were caught only by manual builds. A push-triggered build+test workflow turns every commit into a verified commit, and gives every subsequent plan in `plans/` an automatic verification gate.

## Current state

- `.github/workflows/` contains exactly one file: `static.yml` (GitHub Pages deploy of `docs/public/` on push to `main`). Do not modify it.
- The app requires **Xcode 26+** (iOS 26 SDK). Local dev uses the destination `platform=iOS Simulator,name=iPhone 17 Pro` (iOS 26.2).
- Unit tests live in the `TenraTests` target (swift-testing `@Suite`/`@Test` style). UI tests in `TenraUITests` are template stubs — do not run them in CI (slow, no value).
- The canonical local commands (from CLAUDE.md):

```bash
# Build
xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Unit tests
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests
```

- Reliable result parsing (documented repo convention — do NOT grep for `expect`, it matches `#expect` compiler warnings):

```bash
grep -aE "Test case .* (passed|failed)|\*\* TEST (SUCCEEDED|FAILED)"
```

- The project uses `PBXFileSystemSynchronizedRootGroup` — files on disk are auto-included in targets; no pbxproj edits are ever needed for new files.

## Commands you will need

| Purpose | Command | Expected on success |
|---|---|---|
| Validate workflow syntax locally | `gh workflow list` (after push) or a YAML linter | parses cleanly |
| Local sanity build | `xcodebuild build -scheme Tenra -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 \| grep -E "error:" \| head -30` | no output (no errors) |
| Watch a CI run (after the operator pushes) | `gh run watch` | conclusion: success |

## Scope

**In scope** (the only files you should create/modify):
- `.github/workflows/ci.yml` (create)
- `CLAUDE.md` (one short subsection documenting CI exists; optional)
- `plans/README.md` (status row)

**Out of scope** (do NOT touch):
- `.github/workflows/static.yml` — the Pages deploy; unrelated.
- Any Swift source or test file. If the test suite fails in CI for a real test reason, that is a finding to report, not something this plan fixes.
- `Tenra.xcodeproj/` — no project-setting changes.

## Git workflow

- Work directly on `main` (repo owner's stated preference — no branches/worktrees).
- Do **NOT** push — the owner pushes manually. The workflow will be validated on their next push.
- Commit message style: short descriptive line (see `git log --oneline`), ending with `Co-Authored-By: Claude <noreply@anthropic.com>`.

## Steps

### Step 1: Determine the runner image and Xcode version availability

GitHub-hosted macOS runners ship specific Xcode versions per image. This project needs **Xcode 26.x with an iOS 26.x simulator runtime**. Check the current runner image documentation:

- Fetch `https://github.com/actions/runner-images` README (or `https://raw.githubusercontent.com/actions/runner-images/main/images/macos/macos-26-Readme.md` and the `macos-15` variant) and confirm which image carries Xcode 26.x.
- Pick the newest image that includes Xcode ≥ 26.0 (`macos-26` if it exists, else `macos-15` with an explicit `xcode-select`).

**Verify**: you can name the image and the exact Xcode version string it ships. If **no** GitHub-hosted image ships Xcode ≥ 26 → STOP condition (see below).

### Step 2: Create `.github/workflows/ci.yml`

Create the workflow with this shape (adjust the `runs-on` image and `DEVELOPER_DIR` to what Step 1 found). Key design points, all deliberate:

- Trigger on `push` to `main` and `workflow_dispatch`, with `paths-ignore` for `docs/**` and `plans/**` so docs-only commits don't burn macOS minutes.
- Do not hardcode `iPhone 17 Pro` — the runner's simulator inventory differs from the dev machine. Resolve the first available iPhone simulator for the installed iOS 26 runtime at job time.
- `timeout-minutes: 60` (Xcode cold builds on hosted runners are slow).
- Fail the job on `** TEST FAILED **`.

```yaml
name: CI

on:
  push:
    branches: [main]
    paths-ignore:
      - 'docs/**'
      - 'plans/**'
      - '**.md'
  workflow_dispatch:

jobs:
  build-and-test:
    runs-on: macos-26          # ← from Step 1
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_26.0.app   # ← exact path from Step 1

      - name: Resolve simulator destination
        id: sim
        run: |
          DEVICE=$(xcrun simctl list devices available | grep -E "iPhone" | head -1 | sed -E 's/^ *([^(]+) \(.*/\1/' | sed 's/ *$//')
          if [ -z "$DEVICE" ]; then echo "No iPhone simulator available"; exit 1; fi
          echo "device=$DEVICE" >> "$GITHUB_OUTPUT"
          echo "Using simulator: $DEVICE"

      - name: Build and run unit tests
        run: |
          set -o pipefail
          xcodebuild test \
            -scheme Tenra \
            -destination "platform=iOS Simulator,name=${{ steps.sim.outputs.device }}" \
            -only-testing:TenraTests \
            2>&1 | tee xcodebuild.log | grep -aE "Test case .* (passed|failed)|error:|\*\* TEST (SUCCEEDED|FAILED)" || true
          grep -aq "\*\* TEST SUCCEEDED \*\*" xcodebuild.log

      - name: Upload log on failure
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: xcodebuild-log
          path: xcodebuild.log
```

**Verify**: the YAML parses (`python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` → exit 0).

### Step 3: Sanity-check the test suite passes locally before committing

The workflow is only useful if the suite is green at the commit that introduces it.

**Verify**:
```bash
xcodebuild test -scheme Tenra \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TenraTests 2>&1 | grep -aE "\*\* TEST (SUCCEEDED|FAILED)"
```
→ `** TEST SUCCEEDED **`. If it FAILS at the current HEAD, STOP and report which suite fails (pre-existing breakage is a finding, not yours to fix here).

### Step 4: Commit

Commit `.github/workflows/ci.yml` (and the optional CLAUDE.md note) directly to `main`. Do not push.

**Verify**: `git status` → clean working tree apart from files you did not create; `git log -1 --stat` shows only in-scope files.

## Test plan

This plan adds no Swift tests. Its test is the workflow itself running green on the owner's next push (`gh run watch` → success). Until then the local Step 3 run is the gate.

## Done criteria

- [ ] `.github/workflows/ci.yml` exists and parses as valid YAML
- [ ] Local `xcodebuild test ... -only-testing:TenraTests` → `** TEST SUCCEEDED **`
- [ ] `static.yml` untouched (`git diff 4392be3..HEAD -- .github/workflows/static.yml` → empty)
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Step 1 finds **no** GitHub-hosted macOS image with Xcode ≥ 26. Report the available versions; the fallback decision (self-hosted runner, or `workflow_dispatch`-only workflow that waits for image updates) belongs to the owner.
- The local test run in Step 3 fails at current HEAD (pre-existing breakage).
- You find yourself wanting to edit any Swift file to make CI pass.

## Maintenance notes

- When Xcode/iOS versions bump (the project tracks beta SDKs), the `xcode-select` path in the workflow is the only thing to update.
- If a future plan adds UI tests worth running, add a separate job — keep the unit-test job fast.
- Runner minutes: macOS runners bill at 10× Linux; the `paths-ignore` list keeps docs commits free. If billing becomes a concern, change the trigger to `workflow_dispatch` + a weekly `schedule`.
