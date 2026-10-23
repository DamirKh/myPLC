<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
local kind = request:data("kind")
if "pump" ~= kind then
   kind = "room"
end
local range = tonumber(request:data("range"))
if not range then
   range = "pump" == kind and 86400 or 604800
end
local items = app.get_history(kind, range)
response:write(ba.json.encode({ ok = true, kind = kind, items = items }))
?>
