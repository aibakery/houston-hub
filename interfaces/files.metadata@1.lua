-- Reference implementation over a fictional storage service. IDs are opaque.
local function statFile(id: string): {id: string, name: string, isFolder: boolean, size: number?}
    assert(id ~= "", "file ID must be nonempty")
    local response = http.request({
        method = "POST", url = "https://interface.example.com/stat",
        headers = {["Content-Type"] = "application/json"},
        body = json.encode({id = id}),
    })
    assert(response.status == 200, "file is unavailable")
    local file = json.decode(response.body)
    local result: {id: string, name: string, isFolder: boolean, size: number?} = {
        id = file.id, name = file.name, isFolder = file.isFolder,
    }
    if not file.isFolder then result.size = file.size end
    return result
end

return {statFile = statFile}
