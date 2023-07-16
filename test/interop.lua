
local fs = js.import('fs/promises')

print(tostring(fs.readFile('package.json')))
