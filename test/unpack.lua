
local function unpack(t, from)
    from = from or 1
    if #t < from then
        return 
    else
        return t[from], unpack(t, from + 1)
    end
end

print(unpack({1, 2, 3}))
