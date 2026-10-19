<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
if "POST" ~= request:method() then
   response:setstatus(405)
   response:write(ba.json.encode({ ok = false, error = "POST required" }))
   return
end
if request:data("clear") then
   local ok, err = app.clear_override()
   response:write(ba.json.encode({ ok = ok, error = ok and nil or err }))
   return
end
local target = tonumber(request:data("target"))
local ok, result = app.set_target(target, request:data("hours"))
if ok then
   response:write(ba.json.encode({ ok = true, target = result }))
else
   response:setstatus(400)
   response:write(ba.json.encode({ ok = false, error = tostring(result) }))
end
?>
