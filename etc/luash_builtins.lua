-- LuaSH builtins
-- e.g. cd

local sys = require("syscalls")
local sh = require("sh")
function sh.cd(dir)
  sys.chdir(dir or os.getenv("HOME") or "/")
  sh._PS1 = sys.getcwd().."> "
end
sh.pwd = sys.getcwd
sh.echo = print
sh._PS1 = sys.getcwd().."> "
