local SyntaxHighlighter = require("../ui/controls/SyntaxHighlighter")

local highlighted = SyntaxHighlighter.highlight(
    'local remote = game:GetService("ReplicatedStorage")\nif remote ~= nil then -- ready\n    return 0x2A\nend'
)

assert(highlighted:find('<font color="#C586C0">local</font>', 1, true))
assert(highlighted:find('<font color="#4EC9B0">game</font>', 1, true))
assert(highlighted:find('<font color="#DCDCAA">GetService</font>', 1, true))
assert(highlighted:find('<font color="#CE9178">"ReplicatedStorage"</font>', 1, true))
assert(highlighted:find('<font color="#6A9955">-- ready</font>', 1, true))
assert(highlighted:find('<font color="#B5CEA8">0x2A</font>', 1, true))

local escaped = SyntaxHighlighter.highlight("if left < right and right > 0 then")
assert(escaped:find("&lt;", 1, true))
assert(escaped:find("&gt;", 1, true))

local information = SyntaxHighlighter.highlightFunctionInfo("From Actor: false\nCalling Line: 22")
assert(information:find('<font color="#9CDCFE">From Actor:</font>', 1, true))
assert(information:find('<font color="#C586C0">false</font>', 1, true))
assert(information:find('<font color="#B5CEA8">22</font>', 1, true))

print("syntax_highlighter: ok")
