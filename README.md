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
- Optionally captures bindable calls.
- Captures incoming `OnClientEvent` traffic for reliable and unreliable events.
- Captures `RemoteFunction.OnClientInvoke` arguments and returns when the executor supports `getcallbackvalue`.
- Preserves trailing `nil` arguments and multiple return values with packed tuples.
- Resolves copied event payloads back to retained calls by stable call ID for executor compatibility.
- Records direction, method, calling script/function when available, errors, blocked state, and duration.
- Keeps a bounded per-remote history, with pause/resume, search, export, replay, block, ignore, and argument conditions.
- Treats incoming calls as client receiver activity: local replay, receiver-script paths, and receiver-function spying replace misleading server-caller actions.
- Supports mouse, touch dragging, and long-press context menus.

Generated calls use bounded, cycle-safe serialization for tables, buffers, instances, enums, `DateTime`, `NumberRange`, sequences, vectors, CFrames, parameter objects, and other common Roblox datatypes.

## Configuration

Set configuration before loading `init.lua`:

```lua
getgenv().HydroxideConfig = {
    CaptureIncoming = true,
    MaxRemoteLogs = 500,
    MaxSerializedDepth = 7,
    MaxSerializedEntries = 150,
    MaxSerializedString = 16384,
}
```

The loader works without filesystem APIs. If `readfile` and `writefile` are available, source modules are cached by the current branch commit. Capability and executor information is available through `oh.Capabilities`, `oh.Executor`, and `oh.Failures`.

The original Roblox UI models remain supported. Local model overrides can remove that external dependency; see [assets/README.md](assets/README.md).

## Executor support

RemoteSpy requires `checkcaller` and `hookfunction`. Other capabilities degrade independently:

- `getcallbackvalue` enables incoming `OnClientInvoke` capture.
- `getcallingscript` and `debug.getinfo` add call-site metadata.
- `setclipboard` enables copy/export actions.
- `gethui` provides hidden UI parenting; `CoreGui` is the fallback.
- Filesystem APIs enable source caching but are not required.

## Other tools

- ClosureSpy with reload-safe hook restoration and bounded packed-argument logs.
- Upvalue and constant scanners with editing support.
- Script and module scanners with modern script enumerators and GC fallback.

## Development

The repository includes StyLua, Luau LSP, executor-global definitions, and a formatting workflow. Run:

```powershell
npx.cmd -y @johnnymorganz/stylua-bin@2.5.2 --check .
```

Runtime validation still needs to be performed in a supported executor because ordinary Luau tooling cannot emulate executor hook semantics or Roblox networking.
