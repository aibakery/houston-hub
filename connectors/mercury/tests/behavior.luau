return {
 scenario = {publisher = {}, config = {access = "read-write"}, auth_method = "token", auth_config = {token = "fixture-private-mercury-token"}},
 configure = function()
  calls = 0
  status = 200
  payload = '{}'
  responseHeaders = {}
  fs = fixture.files()
  local f = fs.open("receipt.pdf", "w"); f:write("%PDF-receipt"); await(f:close())
  local multipart = http.multipart
  http = {multipart = multipart, request = function(req)
   calls += 1
   request = req
   if type(req.body) == "userdata" then uploaded = await(req.body:readAll()) end
   return fixture.operation({statusCode = status, headers = responseHeaders, body = fixture.reader(payload)})
  end}
 end,
 run = function(c)
  local function rejected(fn, expected)
   local before = calls
   local ok, err = pcall(fn)
   assert(not ok and string.find(tostring(err), expected, 1, true), "wrong validation error: " .. tostring(err))
   assert(calls == before, "invalid input reached Mercury")
  end
  assert(c.revealCardPan == nil)
  for _, limit in {0, 1001, 1.5, "10", json.decode("null")} do
   rejected(function() c.getAccounts({limit = limit}) end, "limit")
  end
  rejected(function() c.getAccounts({start_after = "a", end_before = "b"}) end, "cannot be combined")
  rejected(function() c.getAccounts({order = "newest"}) end, "unsupported value")
  rejected(function() c.getAccounts({unknown = true}) end, "unknown option")
  rejected(function() c.listCards({isAgentCard = "false"}) end, "boolean")
  rejected(function() c.getSafeRequest({safeRequestId = "../accounts"}) end, "must be an ID")
  rejected(function() c.getSafeRequest({safeRequestId = ""}) end, "nonempty")
  rejected(function() c.getSafeRequest() end, "nonempty")
  rejected(function() c.getSafeRequestDocument({safeRequestId = "s"}) end, "path")
  rejected(function() c.createTransaction({accountId = "a"}) end, "required")
  rejected(function() c.createTransaction({accountId = "a", recipientId = "r", amount = -1, paymentMethod = "ach", idempotencyKey = "key"}) end, "positive")
  rejected(function() c.createCard({userId = "u", kind = "debit", type = "physical"}) end, "virtual")
  rejected(function() c.uploadTransactionAttachment({transactionId = "t", path = "receipt.pdf", attachmentType = "tax"}) end, "attachmentType")
  rejected(function() c.uploadRecipientAttachment({recipientId = "r", path = "receipt.pdf", filename = "bad\r\nname"}) end, "filename")

  payload = '{"transactions":[],"page":{"nextPage":"next-id"},"future":{"field":null}}'
  local opts = {limit = 2, start_after = "cursor-a", search = "Invoice & #1/2", status = "pending"}
  local page = c.listTransactions(opts)
  assert(request.url == "https://api.mercury.com/api/v1/transactions?limit=2&search=Invoice%20%26%20%231%2F2&start_after=cursor-a&status=pending")
  assert(opts.search == "Invoice & #1/2" and page.page.nextPage == "next-id")
  assert(json.encode(page.transactions) == "[]" and page.future.field == json.decode("null"))
  payload = '{"transactions":[{"id":"tx","amount":-123.45}],"page":{}}'
  local nextPage = c.listTransactions({start_after = page.page.nextPage, limit = 2})
  assert(nextPage.transactions[1].amount == -123.45)
  assert(string.find(request.url, "start_after=next-id", 1, true))
  payload = '{"transactions":[],"total":10}'
  c.listAccountTransactions({accountId = "a", offset = 2, limit = 2})
  assert(request.url == "https://api.mercury.com/api/v1/account/a/transactions?limit=2&offset=2")
  payload = '{"transactions":[],"cursor":17}'
  assert(c.getTreasuryTransactions({treasuryId = "tr", cursor = 12}).cursor == 17)
  assert(request.url == "https://api.mercury.com/api/v1/treasury/tr/transactions?cursor=12")
  payload = '{"cards":[],"page":{}}'
  c.listCards({isAgentCard = false})
  assert(string.find(request.url, "isAgentCard=false", 1, true))

  payload = '{"id":"tx","note":null,"categoryData":null}'
  c.updateTransaction({transactionId = "tx", note = json.decode("null"), categoryId = json.decode("null")})
  local body = json.decode(request.body)
  assert(body.note == json.decode("null") and body.categoryId == json.decode("null") and body.transactionId == nil)
  payload = '{"id":"recipient","emails":[]}'
  c.createRecipient({name = "Vendor", emails = json.decode("[]"), electronicRoutingInfo = {accountNumber = "synthetic", routingNumber = "synthetic"}})
  body = json.decode(request.body)
  assert(json.encode(body.emails) == "[]" and body.electronicRoutingInfo.accountNumber == "synthetic")
  payload = '{"id":"tx","status":"pending"}'
  local payment = {accountId = "a", recipientId = "r", amount = 12.34, paymentMethod = "ach", idempotencyKey = "same-intended-payment"}
  c.createTransaction(payment)
  body = json.decode(request.body)
  assert(body.amount == 12.34 and body.idempotencyKey == payment.idempotencyKey and body.accountId == nil)

  payload = '{"attachmentId":"attachment-1","downloadUrl":"https://example.invalid/signed"}'
  c.uploadTransactionAttachment({transactionId = "t", path = "receipt.pdf", filename = "bill.pdf", contentType = "application/pdf", attachmentType = "bill"})
  assert(string.find(uploaded, 'name="attachmentType"', 1, true) and string.find(uploaded, "\r\nbill\r\n", 1, true))
  assert(string.find(uploaded, 'filename="bill.pdf"', 1, true) and string.find(uploaded, "%PDF-receipt", 1, true))

  for _, raw in {"", "null", "\n null \n"} do
   payload = raw
   assert(c.cancelInvoice({invoiceId = "i"}).success)
  end
  for _, raw in {"{}", "[]"} do
   payload = raw
   assert(json.encode(c.cancelInvoice({invoiceId = "i"})) == raw)
  end
  status = 204
  assert(c.deleteRecipient({recipientId = "r"}).success)
  status = 200
  for _, bad in {"not-json", "null", "[]", '{"error":"failed"}', '{"accounts":{}}', '{}'} do
   payload = bad
   local before = calls
   local ok = pcall(c.getAccounts)
   assert(not ok and calls == before + 1, "malformed upstream response accepted/retried")
  end
  payload = '{}'
  assert(not pcall(c.getSafeRequests), "SAFE object accepted as an array")
  for _, code in {401, 403, 404, 422, 429, 500} do
   status = code
   payload = '{"error":"synthetic provider rejection"}'
   responseHeaders = {["retry-after"] = {"15"}}
   local before = calls
   local ok, err = pcall(function() c.createTransaction(payment) end)
   assert(not ok and calls == before + 1, "failed payment retried")
   assert(string.find(tostring(err), tostring(code), 1, true), "provider status lost")
  end
  status = 200
  payload = '{"error":"not a PDF"}'
  responseHeaders = {["content-type"] = {"application/json"}}
  assert(not pcall(function() c.getSafeRequestDocument({safeRequestId = "s", path = "not-created.pdf"}) end))
  assert(not await(fs.exists("not-created.pdf")), "error document was saved")
 end,
}
