# Hydroxide

Luau runtime introspection and network-capture tools for Roblox.

![Hydroxide UI](https://raw.githubusercontent.com/tessa-says-hi/Hydroxide/revision/github-assets/ui.png)

## Load

```lua
local owner = "tessa-says-hi"
local branch = "revision"

local function webImport(file)
    local url = ("https://raw.githubusercontent.com/%s/Hydroxide/%s/%s.lua"):format(owner, branch, file)
    local source = game:HttpGet(url)
    local chunk, compileError = loadstring(source, "@" .. file .. ".lua")
    assert(chunk, compileError)
    return chunk()
end

webImport("init")
webImport("ui/main")
```

Running the loader again calls `oh.Exit()` first, disconnects listeners, restores tracked hooks, and replaces the UI instead of stacking another copy.

## RemoteSpy updates

- Captures outgoing `RemoteEvent:FireServer`, `UnreliableRemoteEvent:FireServer`, and `RemoteFunction:InvokeServer` calls, including cached method references.
- Uses both `__namecall` and direct method hooks so normal `:` calls and cached method calls are captured across executors.
- Optionally captures bindable calls.
- Captures incoming `OnClientEvent` traffic for reliable and unreliable events.
- Captures `RemoteFunction.OnClientInvoke` arguments and returns when the executor supports `getcallbackvalue`.
- Captures outgoing calls made from parallel Luau states, including cached method references created before Hydroxide loads. Executors with `getactorstates` use stable Lua-state IDs; `getactors` and `run_on_actor` remain the compatibility fallback.
- Preserves trailing `nil` arguments and multiple return values with packed tuples.
- Resolves copied event payloads back to retained calls by stable call ID for executor compatibility.
- Records direction, method, calling script/function when available, errors, blocked state, and duration.
- Keeps bounded per-remote and global byte-limited history, with pause/resume, search, export, replay, block, ignore, and argument conditions.
- Splits the Remote Spy list into Incoming and Outgoing views with independent counts. Bindable traffic is grouped under Outgoing as local client activity.
- Tracks block and ignore state independently for incoming, outgoing, and local calls; list-level controls apply to the direction currently being viewed.
- Disables enabled `OnClientEvent` receiver connections while incoming calls are blocked, monitors for new receivers, and restores only the connections Hydroxide disabled.
- Can opt in to executor-originated call capture and labels those calls in logs and exports.
- Treats incoming calls as client receiver activity: local replay, receiver-script paths, and receiver-function spying replace misleading server-caller actions.
- Supports mouse, touch dragging, and long-press context menus.

Generated calls use bounded, cycle-safe serialization for tables, buffers, instances, enums, `DateTime`, `NumberRange`, sequences, vectors, CFrames, parameter objects, and other common Roblox datatypes.

## Configuration

Set configuration before loading `init.lua`:

```lua
getgenv().HydroxideConfig = {
    CaptureActors = true,
    CaptureExecutorCalls = false,
    CaptureIncoming = true,
    MaxRemoteLogBytes = 8 * 1024 * 1024,
    MaxRemoteLogs = 500,
    MaxSerializedDepth = 7,
    MaxSerializedEntries = 150,
    MaxSerializedString = 16384,
}
```

The loader works without filesystem APIs. If `readfile` and `writefile` are available, source modules are cached by the current branch commit. Capability and executor information is available through `oh.Capabilities`, `oh.Executor`, and `oh.Failures`. `oh.RemoteSpyDiagnostics()` reports the selected Actor backend, stable state and hook counts, failures, incoming connection control, and retained payload bytes.

`MaxRemoteLogBytes` limits raw retained arguments, returns, and errors across all remotes. A single payload larger than the limit is dropped while its compact call metadata remains visible. `CaptureExecutorCalls` is disabled by default to avoid logging Hydroxide replays and other executor tooling unless explicitly requested.

The original Roblox UI models remain supported. Local model overrides can remove that external dependency; see [assets/README.md](assets/README.md).

## Executor support

RemoteSpy requires `checkcaller` and `hookfunction`. Other capabilities degrade independently:

- `hookmetamethod` and `getnamecallmethod` enable normal `:` call capture on executors whose direct method hooks only cover cached references.
- `getcallbackvalue` enables incoming `OnClientInvoke` capture.
- `getconnections` enables incoming event receiver inspection, local replay, and reversible incoming blocking.
- `getactorstates` enables the preferred parallel-Luau backend. Hydroxide executes its hooks in every returned `LuaStateProxy`, deduplicates refreshed proxies by `state.Id`, and uses `on_actor_state_created` with `getluastate` when available to instrument new states before their scripts cache methods.
- `getactors` plus `run_on_actor` remains the parallel-Luau fallback for executors without Lua-state proxies.
- `getcallingscript` and `debug.getinfo` add call-site metadata.
- `setclipboard` enables copy/export actions.
- `gethui` provides hidden UI parenting; `CoreGui` is the fallback.
- Filesystem APIs enable source caching but are not required.

## Other tools

- ClosureSpy with reload-safe hook restoration and bounded packed-argument logs.
- Upvalue and constant scanners with editing support.
- Script and module scanners with modern script enumerators and GC fallback.

## Development

The repository includes StyLua, Luau LSP, executor-global definitions, runtime contract tests, and a formatting workflow. Run:

```powershell
npx.cmd -y @johnnymorganz/stylua-bin@2.5.2 --check .
```

GitHub Actions runs the tests in `tests/*.luau`. Actual hook behavior cannot be emulated by a GitHub-hosted Luau process, so `tests/executor-smoke.lua` is the companion live test: execute it through the executor MCP server, then read `getgenv().HydroxideExecutorSmokeReport`. It uses only a temporary local `BindableEvent`, restores its hook, and never calls a server remote.
