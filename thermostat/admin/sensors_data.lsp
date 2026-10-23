<?lsp
response:setheader("Content-Type", "application/json")
response:setheader("Cache-Control", "no-store")
if not app.pin_valid(request) then
   response:setstatus(401)
   response:write(ba.json.encode({ ok = false, error = "PIN required" }))
   return
end
response:write(ba.json.encode(app.get_sensor_table()))
?>
