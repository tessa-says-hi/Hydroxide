type Packed<T> = { [number]: T, n: number }
type LuaStateProxy = {
    Event: any,
    Id: number,
    IsActorState: boolean,
    Execute: (self: LuaStateProxy, source: string, ...any) -> (),
    GetActors: (self: LuaStateProxy) -> { Actor },
}
type CommChannelReceiver = {
    Event: RBXScriptSignal,
    Internal: BindableEvent,
    connect: (self: CommChannelReceiver, callback: (...any) -> ()) -> RBXScriptConnection,
}

declare function getgenv(): { [any]: any }
declare function identifyexecutor(): (string, string?)
declare function checkcaller(): boolean
declare function newcclosure<T>(callback: T): T
declare function hookfunction<T>(target: T, replacement: T): T
declare function restorefunction(target: (...any) -> ...any): ()
declare function isexecutorclosure(target: (...any) -> ...any): boolean
declare function getcallingscript(): Instance?
declare function getcallbackvalue(instance: Instance, property: string): any
declare function getconnections(signal: RBXScriptSignal): { any }
declare function create_comm_channel(): (number, CommChannelReceiver)
declare function createcommchannel(): (number, CommChannelReceiver)
declare function get_comm_channel(id: number): BindableEvent
declare function getcommchannel(id: number): BindableEvent
declare function getactorstates(): { LuaStateProxy }
declare function get_actor_states(): { LuaStateProxy }
declare function getactors(): { Actor }
declare function get_actors(): { Actor }
declare function getgamestate(): LuaStateProxy?
declare function get_game_state(): LuaStateProxy?
declare function getluastate(source: Actor | LuaSourceContainer?): LuaStateProxy?
declare function get_lua_state(source: Actor | LuaSourceContainer?): LuaStateProxy?
declare function run_on_actor(actor: Actor, source: string): any
declare function runonactor(actor: Actor, source: string): any
declare on_actor_state_created: any
declare onactorstatecreated: any
declare oth: {
    get_original_thread: () -> thread?,
    get_root_callback: () -> ((...any) -> ...any)?,
    hook: (target: (...any) -> ...any, callback: (...any) -> ...any) -> (...any) -> ...any,
    is_hook_thread: () -> boolean,
    unhook: (target: (...any) -> ...any) -> boolean,
}
declare function getgc(includeTables: boolean?): { any }
declare function getloadedmodules(excludeCore: boolean?): { ModuleScript }
declare function getrunningscripts(): { LuaSourceContainer }
declare function getscripts(): { LuaSourceContainer }
declare function getsenv(source: LuaSourceContainer): { [any]: any }
declare function getscriptclosure(source: LuaSourceContainer): (...any) -> ...any
declare function getscriptbytecode(source: LuaSourceContainer): string
declare function getscripthash(source: LuaSourceContainer): string
declare function getthreadidentity(): number
declare function setthreadidentity(identity: number): ()
declare function gethui(): Instance
declare function cloneref<T>(instance: T): T
declare function compareinstances(a: Instance, b: Instance): boolean
declare function decompile(source: LuaSourceContainer): string
declare function decompile_script(source: LuaSourceContainer): string
declare function setclipboard(content: string): ()
declare function readfile(path: string): string
declare function writefile(path: string, content: string): ()
declare function isfile(path: string): boolean
declare function isfolder(path: string): boolean
declare function makefolder(path: string): ()
declare function getcustomasset(path: string, noCache: boolean?): string
declare function loadstring(source: string, chunkName: string?): ((...any) -> ...any)?, string?

declare debug: {
  getconstant: (target: (...any) -> ...any, index: number) -> any,
  getconstants: (target: (...any) -> ...any) -> { any },
  getinfo: (target: ((...any) -> ...any) | number) -> { [string]: any },
  getproto: (target: (...any) -> ...any, index: number, active: boolean?) -> any,
  getprotos: (target: (...any) -> ...any) -> { (...any) -> ...any },
  getstack: (level: number, index: number?) -> any,
  getupvalue: (target: (...any) -> ...any, index: number) -> any,
  getupvalues: (target: (...any) -> ...any) -> { any },
  setconstant: (target: (...any) -> ...any, index: number, value: any) -> (),
  setstack: (level: number, index: number, value: any) -> (),
  setupvalue: (target: (...any) -> ...any, index: number, value: any) -> ()
}
