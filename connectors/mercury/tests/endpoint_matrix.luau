-- Expected requests and responses taken from Mercury's published OpenAPI definitions.
return {
 scenario = {publisher = {}, config = {access = "read-write", reveal_card_details = true}, auth_method = "token", auth_config = {token = "fixture-private-mercury-token"}},
 configure = function()
  requests = {}
  fs = fixture.files()
  local f = fs.open("upload.bin", "w"); f:write("receipt" .. string.char(0, 255)); await(f:close())
  local multipart = http.multipart
  http = {multipart = multipart, request = function(req)
   table.insert(requests, req)
   if type(req.body) == "userdata" then req.uploaded = await(req.body:readAll()) end
   return fixture.operation({statusCode = status, headers = {["content-type"] = {media}}, body = fixture.reader(payload)})
  end}
 end,
 run = function(c)
  local cases = json.decode([==[
[
{"args":{"cardId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"POST","name":"cancelCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001/cancel","vault":false,"write":true},
{"args":{"invoiceId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"POST","name":"cancelInvoice","response":null,"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices/00000000-0000-4000-8000-000000000001/cancel","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"kind":"debit","type":"virtual","userId":"fixture"},"body":true,"kind":"json","method":"POST","name":"createCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"name":"fixture","visibleForCardSpend":false,"visibleForOther":false,"visibleForReimbursements":false},"body":true,"kind":"json","method":"POST","name":"createCategory","response":{"futureField":true},"status":"201","url":"https://api.mercury.com/api/v1/categories","vault":false,"write":true},
{"args":{"email":"fixture","futureField":{"preserve":true},"name":"fixture"},"body":true,"kind":"json","method":"POST","name":"createCustomer","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/customers","vault":false,"write":true},
{"args":{"amount":12.34,"destinationAccountId":"fixture","futureField":{"preserve":true},"idempotencyKey":"fixture","sourceAccountId":"fixture"},"body":true,"kind":"json","method":"POST","name":"createInternalTransfer","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/transfer","vault":false,"write":true},
{"args":{"achDebitEnabled":false,"ccEmails":[],"creditCardEnabled":false,"customerId":"fixture","destinationAccountId":"fixture","dueDate":"fixture","futureField":{"preserve":true},"invoiceDate":"fixture","lineItems":[],"useRealAccountNumber":false},"body":true,"kind":"json","method":"POST","name":"createInvoice","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices","vault":false,"write":true},
{"args":{"emails":[],"futureField":{"preserve":true},"name":"fixture"},"body":true,"kind":"json","method":"POST","name":"createRecipient","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/recipients","vault":false,"write":true},
{"args":{"contactEmail":"fixture","futureField":{"preserve":true},"paymentMethods":[],"requireTaxDocument":false,"sendEmail":false},"body":true,"kind":"json","method":"POST","name":"createRecipientInvite","response":{"futureField":true},"status":"201","url":"https://api.mercury.com/api/v1/recipients/invites","vault":false,"write":true},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001","amount":12.34,"futureField":{"preserve":true},"idempotencyKey":"fixture","paymentMethod":"ach","recipientId":"fixture"},"body":true,"kind":"json","method":"POST","name":"createTransaction","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/transactions","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"url":"fixture"},"body":true,"kind":"json","method":"POST","name":"createWebhook","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/webhooks","vault":false,"write":true},
{"args":{"expenseCategoryId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"DELETE","name":"deleteCategory","response":null,"status":"204","url":"https://api.mercury.com/api/v1/categories/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"customerId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"DELETE","name":"deleteCustomer","response":null,"status":"200","url":"https://api.mercury.com/api/v1/ar/customers/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"recipientId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"DELETE","name":"deleteRecipient","response":null,"status":"204","url":"https://api.mercury.com/api/v1/recipient/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"inviteId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"DELETE","name":"deleteRecipientInvite","response":null,"status":"204","url":"https://api.mercury.com/api/v1/recipients/invites/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"webhookEndpointId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"DELETE","name":"deleteWebhook","response":null,"status":"204","url":"https://api.mercury.com/api/v1/webhooks/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"expenseCategoryId":"00000000-0000-4000-8000-000000000001","futureField":{"preserve":true}},"body":true,"kind":"json","method":"POST","name":"editCategory","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/categories/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"cardId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"POST","name":"freezeCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001/freeze","vault":false,"write":true},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getAccountCards","response":{"cards":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/cards","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getAccounts","response":{"accounts":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/accounts","vault":false,"write":false},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getAccountStatements","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"statements":[]},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/statements","vault":false,"write":false},
{"args":{"attachmentId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getAttachment","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/attachments/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"cardId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"customerId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getCustomer","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/customers/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"eventId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getEvent","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/events/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getEvents","response":{"events":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/events","vault":false,"write":false},
{"args":{"invoiceId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getInvoice","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"invoiceId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"download","method":"GET","name":"getInvoicePdf","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices/00000000-0000-4000-8000-000000000001/pdf","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getOrganization","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/organization","vault":false,"write":false},
{"args":{"recipientId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getRecipient","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/recipient/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"inviteId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getRecipientInvite","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/recipients/invites/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getRecipients","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"recipients":[]},"status":"200","url":"https://api.mercury.com/api/v1/recipients","vault":false,"write":false},
{"args":{"safeRequestId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getSafeRequest","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/safes/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"safeRequestId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"download","method":"GET","name":"getSafeRequestDocument","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/safes/00000000-0000-4000-8000-000000000001/document","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getSafeRequests","response":[{"id":"safe-1","paidAt":null}],"status":"200","url":"https://api.mercury.com/api/v1/safes","vault":false,"write":false},
{"args":{"requestId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getSendMoneyApprovalRequest","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/request-send-money/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"statementId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"download","method":"GET","name":"getStatementPdf","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/statements/00000000-0000-4000-8000-000000000001/pdf","vault":false,"write":false},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001","transactionId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getTransaction","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/transaction/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"transactionId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getTransactionById","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/transaction/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{"requestId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getTransferMoneyApprovalRequest","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/request-transfer/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getTreasury","response":{"accounts":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/treasury","vault":false,"write":false},
{"args":{"treasuryId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getTreasuryStatements","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"statements":[]},"status":"200","url":"https://api.mercury.com/api/v1/treasury/00000000-0000-4000-8000-000000000001/statements","vault":false,"write":false},
{"args":{"treasuryId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getTreasuryTransactions","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"transactions":[]},"status":"200","url":"https://api.mercury.com/api/v1/treasury/00000000-0000-4000-8000-000000000001/transactions","vault":false,"write":false},
{"args":{"userId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getUser","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/users/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getUsers","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"users":[]},"status":"200","url":"https://api.mercury.com/api/v1/users","vault":false,"write":false},
{"args":{"webhookEndpointId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"getWebhook","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/webhooks/00000000-0000-4000-8000-000000000001","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"getWebhooks","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"webhooks":[]},"status":"200","url":"https://api.mercury.com/api/v1/webhooks","vault":false,"write":false},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"listAccountTransactions","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"transactions":[]},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/transactions","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listCards","response":{"cards":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/cards","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listCategories","response":{"categories":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/categories","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listCredit","response":{"accounts":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/credit","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listCustomers","response":{"customers":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/ar/customers","vault":false,"write":false},
{"args":{"invoiceId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"listInvoiceAttachments","response":{"attachments":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices/00000000-0000-4000-8000-000000000001/attachments","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listInvoices","response":{"futureField":true,"invoices":[],"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listMerchants","response":{"data":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/merchants","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listRecipientInvites","response":{"futureField":true,"invites":[],"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/recipients/invites","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listRecipientsAttachments","response":{"attachments":[],"futureField":true,"page":{"nextPage":"cursor-next"}},"status":"200","url":"https://api.mercury.com/api/v1/recipients/attachments","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listSendMoneyApprovalRequests","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"requests":[]},"status":"200","url":"https://api.mercury.com/api/v1/request-send-money","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listTransactions","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"transactions":[]},"status":"200","url":"https://api.mercury.com/api/v1/transactions","vault":false,"write":false},
{"args":{},"body":false,"kind":"json","method":"GET","name":"listTransferMoneyApprovalRequests","response":{"futureField":true,"page":{"nextPage":"cursor-next"},"requests":[]},"status":"200","url":"https://api.mercury.com/api/v1/request-transfer","vault":false,"write":false},
{"args":{"accountId":"00000000-0000-4000-8000-000000000001","amount":12.34,"futureField":{"preserve":true},"idempotencyKey":"fixture","paymentMethod":"ach","recipientId":"fixture"},"body":true,"kind":"json","method":"POST","name":"requestSendMoney","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/account/00000000-0000-4000-8000-000000000001/request-send-money","vault":false,"write":true},
{"args":{"amount":12.34,"destinationAccountId":"fixture","futureField":{"preserve":true},"idempotencyKey":"fixture","sourceAccountId":"fixture"},"body":true,"kind":"json","method":"POST","name":"requestTransferMoney","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/request-transfer","vault":false,"write":true},
{"args":{"cardId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"GET","name":"revealCardPan","response":{"futureField":true},"status":"200","url":"https://vault-api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001/reveal","vault":true,"write":false},
{"args":{"cardId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"json","method":"POST","name":"unfreezeCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001/unfreeze","vault":false,"write":true},
{"args":{"cardId":"00000000-0000-4000-8000-000000000001","futureField":{"preserve":true}},"body":true,"kind":"json","method":"POST","name":"updateCard","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/cards/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"customerId":"00000000-0000-4000-8000-000000000001","email":"fixture","futureField":{"preserve":true},"name":"fixture","resendOpenInvoices":false},"body":true,"kind":"json","method":"POST","name":"updateCustomer","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/customers/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"achDebitEnabled":false,"ccEmails":[],"creditCardEnabled":false,"dueDate":"fixture","futureField":{"preserve":true},"invoiceDate":"fixture","invoiceId":"00000000-0000-4000-8000-000000000001","invoiceNumber":"fixture","lineItems":[],"useRealAccountNumber":false},"body":true,"kind":"json","method":"POST","name":"updateInvoice","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/ar/invoices/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"recipientId":"00000000-0000-4000-8000-000000000001"},"body":true,"kind":"json","method":"POST","name":"updateRecipient","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/recipient/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"transactionId":"00000000-0000-4000-8000-000000000001"},"body":true,"kind":"json","method":"PATCH","name":"updateTransaction","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/transaction/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"webhookEndpointId":"00000000-0000-4000-8000-000000000001"},"body":true,"kind":"json","method":"POST","name":"updateWebhook","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/webhooks/00000000-0000-4000-8000-000000000001","vault":false,"write":true},
{"args":{"recipientId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"upload","method":"POST","name":"uploadRecipientAttachment","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/recipient/00000000-0000-4000-8000-000000000001/attachments","vault":false,"write":true},
{"args":{"transactionId":"00000000-0000-4000-8000-000000000001"},"body":false,"kind":"upload","method":"POST","name":"uploadTransactionAttachment","response":{"futureField":true},"status":"200","url":"https://api.mercury.com/api/v1/transaction/00000000-0000-4000-8000-000000000001/attachments","vault":false,"write":true},
{"args":{"futureField":{"preserve":true},"webhookEndpointId":"00000000-0000-4000-8000-000000000001"},"body":true,"kind":"json","method":"POST","name":"verifyWebhook","response":null,"status":"204","url":"https://api.mercury.com/api/v1/webhooks/00000000-0000-4000-8000-000000000001/verify","vault":false,"write":true}
]
]==])
  local count = 0
  for name in c do if name ~= "help" then count += 1 end end
  assert(count == #cases and count == 73, "documented API surface missing")
  for _, case in cases do
   status = tonumber(case.status)
   media = if case.kind == "download" then "application/pdf" else "application/json"
   payload = if case.kind == "download" then "%PDF-1.7\nfixture" else if status == 204 then "" else json.encode(case.response)
   local input = case.args
   if case.kind == "download" then input.path = case.name .. ".pdf" end
   if case.kind == "upload" then input.path = "upload.bin" end
   local before = json.encode(input)
   local previous = #requests
   local result = c[case.name](input)
   assert(#requests == previous + 1, "unexpected paging/retry: " .. case.name)
   local req = requests[#requests]
   assert(req.method == case.method and req.url == case.url, "wrong request: " .. case.name)
   assert(req.headers.Authorization == nil, "credentials entered Lua")
   assert(json.encode(input) == before, "mutated caller arguments")
   if case.kind == "download" then
    assert(result.path == input.path and result.size == #payload and result.url ~= nil)
    local f = fs.open(result.path, "r"); assert(await(f:readAll()) == payload); f:close()
   elseif status == 204 or case.response == json.decode("null") then
    assert(result.success == true)
   else
    assert(json.encode(result) == json.encode(case.response), "lost response data: " .. case.name)
   end
   if case.body then
    local body = json.decode(req.body)
    assert(body.futureField.preserve, "lost future/nested JSON fields")
    for field in input do
     if string.find(case.url, tostring(input[field]), 1, true) and field ~= "futureField" then
      assert(body[field] == nil, "path field leaked into body")
     end
    end
   elseif case.kind == "upload" then
    assert(string.find(req.headers["Content-Type"][1], "multipart/form-data; boundary=", 1, true))
    assert(string.find(req.uploaded, 'name="file"', 1, true))
    assert(string.find(req.uploaded, "receipt" .. string.char(0, 255), 1, true))
   else
    assert(req.body == nil, "unexpected body")
   end
  end
 end,
}
