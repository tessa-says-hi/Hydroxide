local TextSelection = require("../ui/controls/TextSelection")

local ranges = TextSelection.getRanges("one\ntwo\nthree", 2, 10)
assert(#ranges == 3)
assert(ranges[1].Line == 0 and ranges[1].Prefix == "o" and ranges[1].Text == "ne")
assert(ranges[1].IncludesNewline)
assert(ranges[2].Line == 1 and ranges[2].Prefix == "" and ranges[2].Text == "two")
assert(ranges[2].IncludesNewline)
assert(ranges[3].Line == 2 and ranges[3].Prefix == "" and ranges[3].Text == "t")
assert(not ranges[3].IncludesNewline)

local reversed = TextSelection.getRanges("alpha", 6, 2)
assert(#reversed == 1)
assert(reversed[1].Prefix == "a" and reversed[1].Text == "lpha")

local accented = utf8.char(0xE9)
local unicode = TextSelection.getRanges("a" .. accented .. "bc", 2, 4)
assert(#unicode == 1 and unicode[1].Text == accented)

local cursor = TextSelection.getCursor("first\nsecond", 8)
assert(cursor.Line == 1 and cursor.Prefix == "s")

local trailing = TextSelection.getCursor("line\n", 6)
assert(trailing.Line == 1 and trailing.Prefix == "")

print("text_selection: ok")
