-- sh: Simple LuaSH-based shell.
-- doesn't actually contain much logic; lets the Lua REPL do most of the work

local sh = require("sh")
local sys = require("syscalls")
local argv = ...
local args, opts = require("getopt").getopt({
  options = {
    c = true
  }
}, argv)

local cmdline = {[0] = "luash", "-i", "-l", "sh", "/etc/profile.lua"}
if opts.c and opts.c ~= argv[0] then
  table.insert(cmdline, 4, "dofile('"..opts.c.."')")
  table.insert(cmdline, 4, "-e")
  print(table.unpack(cmdline))
end

sys.exec(sh.resolve("lua"), cmdline)
