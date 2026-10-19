<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
local range = tonumber(request:data("range")) or 86400
local items = app.get_history(range)
response:write(ba.json.encode({ ok = true, items = items }))
?>
