<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
local ok, state = pcall(app.get_state)
if ok then
   response:write(ba.json.encode(state))
else
   response:setstatus(500)
   response:write(ba.json.encode({ ok = false, error = tostring(state) }))
end
?>
