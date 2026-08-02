const fs = require("node:fs");

const target = process.argv[2];
if (!target) {
    throw new Error("Expected an output path");
}

const moduleSource = fs.readFileSync("modules/ActorRemoteSpy.lua", "utf8");
const match = moduleSource.match(/local actorSource = \[==\[\r?\n([\s\S]*?)\r?\n\]==\]/);
if (!match) {
    throw new Error("Actor source payload was not found");
}

const actorSource = match[1]
    .replaceAll("__ACTOR_ID__", "1")
    .replaceAll("__BRIDGE_NAME__", '"HydroxideActorBridge_Test"')
    .replaceAll("__CHANNEL_ID__", "nil")
    .replaceAll("__USE_OTH__", "false")
    .replaceAll("__CAPTURE_EXECUTOR_CALLS__", "false");
fs.writeFileSync(target, actorSource);
