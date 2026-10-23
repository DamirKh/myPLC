local live_buffer = require("modules.live_buffer")

return function(t)
   t.test("records only valid diagnostics", function()
      local buffer = live_buffer.new(600)
      buffer:record({
         diagnostics = {
            { key = "diag:A", ok = true, temp = 21.5 },
            { key = "diag:B", ok = false, temp = 22.0 },
            { key = "diag:C", ok = true, temp = "23" },
         },
      }, 1000)
      local data = buffer:list(1000)
      t.assert_eq(#data.series["diag:A"], 1)
      t.assert_near(data.series["diag:A"][1].v, 21.5)
      t.assert_eq(data.series["diag:B"], nil)
      t.assert_eq(data.series["diag:C"], nil)
   end)

   t.test("updates a value with the same timestamp", function()
      local buffer = live_buffer.new(600)
      buffer:record({ diagnostics = { { key = "diag:A", ok = true, temp = 21 } } }, 1000)
      buffer:record({ diagnostics = { { key = "diag:A", ok = true, temp = 22 } } }, 1000)
      local points = buffer:list(1000).series["diag:A"]
      t.assert_eq(#points, 1)
      t.assert_near(points[1].v, 22)
   end)

   t.test("drops samples older than the window", function()
      local buffer = live_buffer.new(600)
      buffer:record({ diagnostics = { { key = "diag:A", ok = true, temp = 21 } } }, 1000)
      buffer:record({ diagnostics = { { key = "diag:B", ok = true, temp = 22 } } }, 1601)
      local data = buffer:list(1601)
      t.assert_eq(data.series["diag:A"], nil)
      t.assert_eq(#data.series["diag:B"], 1)
   end)

   t.test("prunes when no new samples arrive", function()
      local buffer = live_buffer.new(600)
      buffer:record({ diagnostics = { { key = "diag:A", ok = true, temp = 21 } } }, 1000)
      buffer:prune(1601)
      local data = buffer:list(1601)
      t.assert_eq(next(data.series), nil)
   end)

   t.test("keeps at most max_points", function()
      local buffer = live_buffer.new(600, 3)
      for i = 1, 5 do
         buffer:add("diag:A", i, i)
      end
      local points = buffer:list(5).series["diag:A"]
      t.assert_eq(#points, 3)
      t.assert_eq(points[1].t, 3)
      t.assert_eq(points[3].t, 5)
   end)

   t.test("ignores a missing snapshot", function()
      local buffer = live_buffer.new(600)
      buffer:record(nil, 1000)
      t.assert_eq(next(buffer:list(1000).series), nil)
   end)
end
