-- SH: LuaSH's supporting library
-- This is a modified version of LuaSH, which
-- is (c) 2015 Serge Zaitsev.
-- Changes:
--  - Combine the metatables for _G and sh, and don't set it on _G,
--    so e.g. sh.ls() works
--  - Use some Cynosure 2 syscalls (to be mostly superseded by luaposix
--    eventually)
--  - Add sh.resolve() to search $PATH for a command
--  - Add sh.split() to split a command into tokens
--  - Add sh.expand() to perform glob expansion
--  - Don't use io.popen()

local sys = require("syscalls")
local errno = require("posix.errno").errno
local stdio = require("posix.stdio")
local dirent = require("posix.dirent")

local M = {}

-- converts key and it's argument to "-k" or "-k=v" or just ""
local function arg(k, a)
	if not a then return k end
	if type(a) == 'string' and #a > 0 then return k..'=\''..a..'\'' end
	if type(a) == 'number' then return k..'='..tostring(a) end
	if type(a) == 'boolean' and a == true then return k end
	error('invalid argument type', type(a), a)
end

-- converts nested tables into a flat list of arguments and concatenated input
local function flatten(t)
	local result = {args = {}, input = ''}

	local function f(t)
		local keys = {}
		for k = 1, #t do
			keys[k] = true
			local v = t[k]
			if type(v) == 'table' then
				f(v)
			else
				table.insert(result.args, v)
			end
		end
		for k, v in pairs(t) do
			if k == '__input' then
				result.input = result.input .. v
			elseif not keys[k] and k:sub(1, 1) ~= '_' then
				local key = '-'..k
				if #k > 1 then key = '-' ..key end
				table.insert(result.args, arg(key, v))
			end
		end
	end

	f(t)
	return result
end

local function pread(cmd, inp)
  local pid, err
  local file = M.resolve(cmd[0])

  if not file then
    io.stderr:write("command not found\n")
    return nil, "exit", 127
  end
  local infd, outfd = sys.pipe()
  local inst, oust

  if inp and #inp > 0 then
    inst, oust = sys.pipe()

    pid, err = sys.fork(function()
      assert(sys.dup2(inst, 0))
      assert(sys.dup2(outfd, 1))
      sys.close(inst)
      sys.close(oust)
      sys.close(infd)
      sys.close(outfd)
      local _, _err = sys.execve(file, cmd)
      os.exit(_err)
    end)

    sys.write(oust, inp)
    sys.close(oust)
  else
    pid, err = sys.fork(function()
      assert(sys.dup2(outfd, 1))
      sys.close(infd)
      sys.close(outfd)
      local _, _err = sys.execve(file, cmd)
      os.exit(_err)
    end)
  end

  if not pid then
    sys.close(infd)
    sys.close(outfd)
    if inst then sys.close(inst) end
    error(errno(err))
  end

  local exit, status = sys.wait(pid)
  local output = sys.read(infd, "a")
  sys.close(infd)
  sys.close(outfd)
  if inst then sys.close(inst) end

  return output, exit, status
end

-- returns a function that executes the command with given args and returns its
-- output, exit status etc
local function command(cmd, ...)
	local prearg = {...}
	return function(...)
		local args = flatten({...})
		local s = {[0]=cmd}
		for _, v in ipairs(prearg) do
      s[#s+1] = v
		end
		for _, v in pairs(args.args) do
      s[#s+1] = v
		end

		local output, exit, status = pread(s, args.input)

		local t = {
			__input = output or "",
			__exitcode = exit == 'exit' and status or 127,
			__signal = exit == 'signal' and status or 0,
		}

		local mt = {
			__index = function(_, k)
				return _G[k] or M[k]
			end,
			__tostring = function(self)
				-- return trimmed command output as a string
				return self.__input:match('^%s*(.-)%s*$')
			end
		}
		return setmetatable(t, mt)
	end
end

-- export command() function and configurable temporary "input" file
M.command = command
M.tmpfile = '/tmp/shluainput'

-- allow to call sh to run shell commands
setmetatable(M, {
	__call = function(_, cmd, ...)
		return command(cmd, ...)
	end, __index = function(_, cmd)
    return rawget(M, cmd) or command(cmd)
  end
})

-- new! resolve() and split()
function M.split(str)
  local tokens = {""}
  local i = #tokens
  local instr = false

  for c in str:gmatch(".") do
    if c == "\"" or c == "'" then
      if instr and c == instr then instr = not instr
      else instr = not instr end
    elseif instr then
      tokens[i] = tokens[i] .. c
    elseif c == " " or c == "\n" then
      if #tokens[i] > 0 then
        i = i + 1
        tokens[i] = ""
      end
    else
      tokens[i] = tokens[i] .. c
    end
  end

  return tokens
end

local environ = sys.environ()
function M.resolve(path)
  if path:find("/") then
    local stat = sys.stat(path)
    if stat and bit32.band(stat.mode, 0x8000) ~= 0 then
      return path
    end
  end

  local PATH = environ.PATH or "/bin:/sbin:/usr/bin"
  for search in PATH:gmatch("[^:]+") do
    local test  = search .. "/" .. path
    local test2 = search .. "/" .. path .. ".lua"
    local stat  = sys.stat(test)
    local stat2 = sys.stat(test2)
    if stat and bit32.band(stat.mode, 0x8000) ~= 0 then
      return test
    elseif stat2 and bit32.band(stat2.mode, 0x8000) ~= 0 then
      return test2
    end
  end
  return nil, "command not found"
end

function M.expand(pattern)
  if pattern:sub(1,1) == "*" then
    pattern = "./" .. pattern
  end
  local results = {}
  if pattern:match("[^\\]%*") then
    local _, index = pattern:find("[^\\]%*")
    local base, rest = pattern:sub(1, index-1), pattern:sub(index+1)
    local fname_pat = ".+"
    if base:sub(-1) ~= "/" and #base > 0 then
      local start = base:match("^.+/(.-)$")
      if start then
        base = base:sub(1, -#start - 1)
        fname_pat = require("text").escape(start) .. fname_pat
      end
    end
    if rest:sub(1,1) ~= "/" and #rest > 0 then
      local start = rest:match("^(.-/?)$")
      if start then
        if start:sub(-1) == "/" then start = start:sub(1, -2) end
        rest = rest:sub(#start + 1)
        fname_pat = fname_pat .. require("text").escape(start)
      end
    end
    local files, err = dirent.files(base)
    if not files then
      -- ignore errors for now
      -- TODO: is this correct behavior?
      local res = M.expand(base .. "/" .. rest)
      for i=1, #res, 1 do
        results[#results+1] = res[i]
      end
    else
      table.sort(files)
      for i, file in ipairs(files) do
        if file:sub(-1) == "/" then file = file:sub(1,-2) end
        if file:match(fname_pat) then
          local res = M.expand(base .. file .. rest)
          for i=1, #res, 1 do
            results[#results+1] = res[i]
          end
        end
      end
    end
  end
  if #results == 0 then results = {pattern} end
  return results
end

return M
