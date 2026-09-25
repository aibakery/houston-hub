return function(connector)
    assert(connector.name == "granola")
    assert(type(connector.help) == "string" and #connector.help > 0)
    assert(type(connector.functions) == "table")
    for name, fn in pairs(connector.functions) do
        assert(type(fn) == "function", name .. " must be callable")
    end
end
