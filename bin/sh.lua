-- sh: Simple LuaSH-based shell.
-- doesn't actually contain much logic; lets the Lua REPL do most of the work

local sh = require("sh")
local sys = require("syscalls")
local argv = ...
local args, opts = require("getopt").getopt({
  options = {
    c = true, i = true
  }
}, argv)

local cmdline = {[0] = "luash", "-i", "-l", "sh",
  "-e", "setmetatable(_G, getmetatable(sh))"}
if opts.c and opts.c ~= argv[0] then
  table.insert(cmdline, "-e")
  table.insert(cmdline, "dofile('"..opts.c.."')")
end

if opts.i then
  cmdline[#cmdline+1] = "/etc/profile.lua"
end

sys.execve(sh.resolve("lua"), cmdline)
