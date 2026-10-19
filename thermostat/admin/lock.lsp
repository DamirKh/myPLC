<?lsp
local cookie = response:createcookie("thermo_pin")
cookie:path"/"
cookie:maxage(0)
cookie:httponly(true)
cookie:activate()
response:sendredirect"/"
?>
