-- sh: Simple LuaSH-based shell.
-- doesn't actually contain much logic; lets the Lua REPL do most of the work

local sh = require("sh")
local sys = require("sys")

local cmdline = {[0] = "luash", "-i", "-l", "sh", "/etc/profile.lua"}

sys.exec(sh.resolve("lua"), cmdline)
