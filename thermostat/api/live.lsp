<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
local ok, data = pcall(app.get_live)
if ok then
   response:write(ba.json.encode({
      ok = true,
      window_sec = data.window_sec,
      series = data.series,
   }))
else
   response:setstatus(500)
   response:write(ba.json.encode({ ok = false, error = tostring(data) }))
end
?>
