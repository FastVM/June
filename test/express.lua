
local express = js.import('express').default
local app = express()
local port = 3000

app:get('/', function(req, res)
    res:send 'Hello, World!'
end)

app:listen(port, function()
    print 'app started'
end)
