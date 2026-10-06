-- Reference implementation over a fictional mail service. Tests mock http.request.
local function listMailFolders(): {{id: string, name: string}}
    local response = http.request({url = "https://interface.example.com/folders"})
    assert(response.status == 200, "mail service failed")
    local folders = json.decode(response.body)
    local result: {{id: string, name: string}} = json.decode("[]")
    for _, folder in folders do
        result[#result + 1] = {id = folder.id, name = folder.name}
    end
    table.sort(result, function(a: {id: string, name: string}, b: {id: string, name: string}) return a.id < b.id end)
    return result
end

return {listMailFolders = listMailFolders}
