# Flowgate Improvement Review

This review focuses on correctness, interaction quality, and maintainability across the Go server, Svelte UI, hook binary, Stream Deck integration, and native app.

## Highest Priority

### Resolve the `/api/devices` mismatch

The UI polls `/api/devices`, but the Go server currently registers only `/api/prompt`, `/ws`, and `/api/health`.

- UI polling: `ui/src/lib/stores.ts:424`
- Registered routes: `go-server/main.go:135`

As written, Stream Deck status silently fails because fetch errors are swallowed. Either implement a protected `/api/devices` endpoint backed by the `stream-deck` package, or remove polling from the default UI until a device service is actually running. If implemented, send the same auth token as other API calls and expose the error state in the UI during development.

### Make hook failure mode visible or configurable

When the hook cannot reach the server or gets any non-200 response, it silently allows the tool.

- Silent allow path: `hooks/prompt-hook.go:101`
- Non-200 handling: `hooks/prompt-hook.go:144`
- Passthrough output: `hooks/prompt-hook.go:199`

Fail-open is good for avoiding a broken Claude Code session, but it is risky for a permissions gate. Add a config option such as `FLOWGATE_HOOK_FAILURE_MODE=allow|ask|deny`, default it deliberately, and include a reason in fallback output when not using silent mode. At minimum, log failures to stderr behind a verbose/debug flag so users can diagnose why prompts are not appearing.

## Correctness And Reliability

### Avoid data races in the WebSocket hub

`Hub.isPaused` and the `clients` map are read and written outside a consistent ownership model.

- `isPaused` read on connect: `go-server/handlers/websocket.go:66`
- `isPaused` write on toggle: `go-server/handlers/websocket.go:221`
- `clients` length read outside lock: `go-server/handlers/websocket.go:104`
- delete while holding an `RLock`: `go-server/handlers/websocket.go:83`

Keep all hub-owned state inside the hub event loop or protect it with the mutex consistently. For pause state, prefer `queue.IsPaused()` as the source of truth when sending initial state to a client. In the broadcast case, use a write lock when removing slow clients, or route unregister operations through the existing channel.

### Do not call callbacks while holding the queue lock

`Queue.Resolve` and `Queue.SetPaused` call callbacks while still holding `q.mu`.

- Resolve callback under lock: `go-server/queue/queue.go:173`
- Pause update callback under lock: `go-server/queue/queue.go:222`

Those callbacks broadcast through the hub and can block on channels. That creates avoidable coupling between queue state and client delivery. Capture callback payloads while locked, release the lock, then broadcast. This makes timer callbacks, UI actions, and prompt additions less likely to stall each other.

### Fix closure capture in resumed timers

When resuming paused timers, the timer callback closes over the loop variable `id`.

- Timer callback inside loop: `go-server/queue/queue.go:263`
- Closure uses `id`: `go-server/queue/queue.go:271`

Modern Go has improved range semantics, but this project declares `go 1.21`, where the older closure pitfall is still relevant depending on toolchain behavior. Create a local `promptID := id` before `time.AfterFunc` and use that inside the callback.

### Return immutable snapshots from queue getters

`Queue.List` returns pointers to internal `Prompt` objects, and `Queue.GetSettings` returns the internal settings pointer.

- Prompt pointer list: `go-server/queue/queue.go:210`
- Settings pointer: `go-server/queue/queue.go:296`

This makes it easy for callers to accidentally mutate queue-owned state without holding the queue lock. Return copied prompt structs and a copied settings value, or document the ownership contract and keep all callers read-only. Copying is safer and cheap at the current scale.

### Validate and report WebSocket message decode errors

Several WebSocket handlers ignore JSON marshal/unmarshal errors and invalid payloads.

- Resolve decode: `go-server/handlers/websocket.go:177`
- Settings decode: `go-server/handlers/websocket.go:236`

Use typed message structs, check decode errors, and send a small error response back to the client for invalid settings, invalid decisions, unknown prompt IDs, and failed saves. The UI can then show "Save failed" or "Prompt already resolved" instead of appearing to work.

## Interaction Quality

### Add explicit save state for settings

`Settings.svelte` optimistically updates the local store even if the WebSocket is disconnected or the server rejects the update.

- Optimistic save: `ui/src/lib/Settings.svelte:159`
- `updateSettings` drops messages when disconnected: `ui/src/lib/stores.ts:475`

Disable the save button while disconnected, show dirty/saved/error states, and only mark the local edit as saved after a `settings:updated` echo from the server. Also consider warning when closing the modal with unsaved local edits.

### Improve disconnected and auth-expired feedback

The browser UI auto-reconnects forever, but does not distinguish server-down, auth-failed, and network-disconnected states.

- Reconnect loop: `ui/src/lib/stores.ts:175`
- Declared but unused error store: `ui/src/lib/stores.ts:134`

Populate `connectionError`, show a compact status message, and give the user an action when the stored token is stale. For 401 WebSocket failures, clear the cached token or prompt the user to reopen from the native app with a fresh token.

### Reduce notification and audio permission friction

The app requests notification permission on mount, and calls `Tone.start()` from that flow.

- Mount behavior: `ui/src/App.svelte:51`
- Permission/audio init: `ui/src/lib/stores.ts:359`

Browsers often expect audio startup to happen from a direct user gesture, and notification permission prompts are easier to accept when tied to a clear action. Move notification/audio enablement behind a settings toggle or first prompt interaction, and keep the default quiet until the user opts in.

### Make prompt actions safer for high-risk tools

Keyboard shortcuts allow `y` and number keys to approve prompts immediately.

- Keyboard approval: `ui/src/App.svelte:57`

This is efficient, but risky for `Bash`, write tools, and MCP tools. Consider requiring a modifier for execute/write approvals, or adding a per-category preference such as "keyboard approve read-only prompts only." The UI can still keep one-key deny because denying is the safer action.

### Improve modal accessibility

The settings overlay has a dialog role but lacks focus trapping, Escape handling, and reliable focus restore.

- Dialog markup: `ui/src/lib/Settings.svelte:189`

Add focus management for settings and "Other" modals. At minimum: focus the first input when opened, close on Escape, keep Tab inside the dialog, and restore focus to the button that opened it.

## Maintainability

### Centralize shared protocol types

Prompt, settings, rule, decision, and WebSocket message schemas are represented independently across Go, TypeScript, and Swift.

- Go models: `go-server/models/types.go`
- TypeScript models: `ui/src/lib/types.ts`
- Swift parsing: `native-app/ClaudePrompt/Sources/Services/WebSocketClient.swift:106`

Introduce a schema contract, even if it is a small checked-in JSON Schema plus generated TypeScript types. Use it to validate settings files and WebSocket payloads. This will catch protocol drift before runtime.

### Clean up migration-era docs and names

The codebase still contains `claude-prompt-ui` package names, `CLAUDE_PROMPT_*` environment variables, and older docs that describe removed HTTP endpoints.

- Go module name: `go-server/go.mod:1`
- Hook env vars: `hooks/prompt-hook.go:43`
- Old endpoint docs found in `go-server/ARCHITECTURE.md`, `docs/API.md`, and `native-app/PLAN.md`

Decide whether the public name is Flowgate everywhere. If so, update package names, env vars, binary names, docs, and generated paths in one compatibility-aware pass. Keep old env vars as aliases for one release.

### Split large store responsibilities

`ui/src/lib/stores.ts` handles prompt state, settings state, local preferences, WebSocket transport, audio, browser notifications, and device polling.

- Current store starts at `ui/src/lib/stores.ts:1`

Split it into focused modules: `prompts`, `settings`, `transport`, `notifications`, `devices`, and `toolCategories`. This will make tests smaller and reduce the chance that browser-only side effects break state tests.

## Suggested Implementation Order

1. Fix hub/queue concurrency issues.
2. Resolve or remove `/api/devices` polling.
3. Add settings save/error states and connection diagnostics.
4. Centralize shared protocol definitions.
