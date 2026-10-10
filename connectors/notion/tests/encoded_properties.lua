return {
 scenario={publisher={},config={},auth_method="token",auth_config={token="fixture-notion-private-token"}},
 configure=function()
  requests={}
  http={request=function(req)
   table.insert(requests,req)
   return fixture.operation({statusCode=200,headers={},body=fixture.reader('{"object":"property_item","type":"number","number":42}')})
  end}
 end,
 run=function(c)
  -- Real encoded short ID used in Notion's property object documentation.
  c.getPageProperty({page_id="page",property_id="f%5C%5C%3Ap"})
  assert(requests[1].url=="https://api.notion.com/v1/pages/page/properties/f%5C%5C%3Ap")
  c.getPageProperty({page_id="page",property_id="f\\\\:p"})
  assert(requests[2].url==requests[1].url,"encoded and raw Notion property IDs must agree")
 end,
}
