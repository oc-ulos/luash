# LuaSH

A two-part shell (half library, half REPL) for ULOS 2.  Its design is heavily inspired by https://github.com/zserge/luash.


## Library
`local sh = require("sh")`

LuaSH can compile basic Bourne-stype statements:

`sh.compile("ls /bin | grep .*s.*") = sh.ls("/bin"):grep(".*s.*")`

This is not perfect, and it is recommended to simply use LuaSH's features directly.  For example, `ls /bin | grep $(ls /lib) $filter` = `sh.ls("/bin"):grep(sh.split(sh.ls("/lib")), sh.getenv("filter"))` - so even if there are multiple files in `/lib`, only the first will be passed due to how Lua's varargs work.
