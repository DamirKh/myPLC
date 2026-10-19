local history = require("modules.history")

return function(t)
   t.test("adds and lists in order", function()
      local h = history.new(10)
      h:add({ t = 1 })
      h:add({ t = 2 })
      local list = h:list()
      t.assert_eq(#list, 2)
      t.assert_eq(list[1].t, 1)
      t.assert_eq(list[2].t, 2)
   end)

   t.test("wraps at capacity", function()
      local h = history.new(3)
      for i = 1, 5 do
         h:add({ t = i })
      end
      local list = h:list()
      t.assert_eq(#list, 3)
      t.assert_eq(list[1].t, 3)
      t.assert_eq(list[3].t, 5)
   end)

   t.test("downsamples", function()
      local h = history.new(100)
      for i = 1, 100 do
         h:add({ t = i })
      end
      t.assert_eq(#h:downsample(10), 10)
   end)
end
