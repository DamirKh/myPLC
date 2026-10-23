local history = require("modules.history")

local M = {}

function M.load(io, name, hist)
   local ok, rwfile = pcall(require, "rwfile")
   if not ok then
      return false, tostring(rwfile)
   end
   local data = rwfile.file(io, name)
   if not data then
      return true, 0
   end
   local count = 0
   for line in data:gmatch("[^\r\n]+") do
      local item = history.decode(line)
      if "table" == type(item) and item.t then
         hist:add(item)
         count = count + 1
      end
   end
   return true, count
end

function M.append(io, name, item)
   local line = history.encode(item)
   if not line then
      return false, "encode"
   end
   local fp, err = io:open(name, "a")
   if not fp then
      return false, err
   end
   local ok, write_err = fp:write(line .. "\n")
   local close_ok, close_err = fp:close()
   if not ok then
      return false, write_err
   end
   if nil == close_ok then
      return false, close_err
   end
   return true
end

function M.compact(io, name, hist)
   local lines = {}
   for _, item in ipairs(hist:list()) do
      local line = history.encode(item)
      if line then
         lines[#lines + 1] = line
      end
   end
   local data = table.concat(lines, "\n")
   if #lines > 0 then
      data = data .. "\n"
   end
   local ok, rwfile = pcall(require, "rwfile")
   if not ok then
      return false, tostring(rwfile)
   end
   return rwfile.file(io, name, data)
end

function M.size(io, name)
   local stat = io:stat(name)
   return stat and stat.size or 0
end

return M
