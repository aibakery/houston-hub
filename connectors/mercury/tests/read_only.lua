return {
 scenario = {publisher = {}, config = {}, auth_method = "token", auth_config = {token = "fixture-private-mercury-token"}},
 configure = function()
  calls = 0
  http = {request = function(req)
   calls += 1
   assert(req.method == "GET")
   local body
   if string.find(req.url, "/accounts", 1, true) then
    body = '{"accounts":[{"id":"account-1","currentBalance":1234.56,"availableBalance":1200}],"page":{}}'
   elseif string.find(req.url, "/safes/", 1, true) then
    body = '{"id":"safe-1","signedByInvestorAt":"2026-10-01T12:00:00Z","signedByOwnerAt":null,"paidAt":null,"canceledAt":null}'
   else
    body = '[]'
   end
   return fixture.operation({statusCode = 200, headers = {}, body = fixture.reader(body)})
  end}
 end,
 run = function(c)
  local count = 0
  for name in c do
   if name ~= "help" then
    count += 1
   end
  end
  assert(count == 42, "wrong read-only surface")
  for _, name in {"createTransaction", "requestSendMoney", "createInternalTransfer", "requestTransferMoney", "createRecipient", "updateTransaction", "createCard", "freezeCard", "deleteCustomer", "cancelInvoice", "verifyWebhook", "uploadRecipientAttachment", "revealCardPan"} do
   assert(c[name] == nil, "read-only leaked " .. name)
  end
  local account = c.getAccounts().accounts[1]
  assert(account.currentBalance == 1234.56 and account.availableBalance == 1200)
  local safe = c.getSafeRequest({safeRequestId = "safe-1"})
  assert(safe.signedByInvestorAt == "2026-10-01T12:00:00Z" and safe.paidAt == json.decode("null"))
  assert(safe.status == nil, "invented SAFE status")
  assert(json.encode(c.getSafeRequests()) == "[]", "empty SAFE array lost")
  assert(calls == 3)
 end,
}
