local M = {}
M.__index = M

function M.new(capacity)
   return setmetatable({
      capacity = capacity or 2880,
      items = {},
      head = 1,
      count = 0,
   }, M)
end

function M:add(item)
   self.items[self.head] = item
   self.head = (self.head % self.capacity) + 1
   if self.count < self.capacity then
      self.count = self.count + 1
   end
end

function M:list()
   local out = {}
   local start = self.count < self.capacity and 1 or self.head
   for i = 0, self.count - 1 do
      local idx = ((start - 1 + i) % self.capacity) + 1
      out[#out + 1] = self.items[idx]
   end
   return out
end

function M:downsample(max_items)
   local all = self:list()
   if not max_items or #all <= max_items then
      return all
   end
   local out = {}
   local step = #all / max_items
   for i = 0, max_items - 1 do
      local idx = math.floor(i * step) + 1
      out[#out + 1] = all[idx]
   end
   return out
end

function M:clear()
   self.items = {}
   self.head = 1
   self.count = 0
end

function M:size()
   return self.count
end

function M.encode(item)
   if ba and ba.json and ba.json.encode then
      return ba.json.encode(item)
   end
   return nil, "json encoder unavailable"
end

function M.decode(line)
   if ba and ba.json and ba.json.decode then
      return ba.json.decode(line)
   end
   return nil, "json decoder unavailable"
end

return M
