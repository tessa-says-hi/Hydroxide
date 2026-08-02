# Optional local UI assets

Hydroxide still supports its original public Roblox models, but the loader can use local copies so a model becoming private does not break startup.

Place exported copies wherever your executor can read them, then set overrides before loading `init.lua`:

```lua
getgenv().HydroxideAssets = {
    ["rbxassetid://11389137937"] = "hydroxide-assets/interface.rbxm",
    ["rbxassetid://5042114982"] = "hydroxide-assets/components.rbxm",
}
```

An already-loaded `Instance`, an array of instances, another Roblox content ID, or a local path accepted by `getcustomasset` can be used as an override value.
