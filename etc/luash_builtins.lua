-- LuaSH builtins
-- e.g. cd

local sys = require("syscalls")
local sh = require("sh")
function sh.cd(dir)
  sys.chdir(dir or os.getenv("HOME") or "/")
end
sh.pwd = sys.getcwd
sh.echo = print
