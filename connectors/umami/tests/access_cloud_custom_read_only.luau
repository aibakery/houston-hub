return {
 scenario={config={["access"]="custom",["account"]="read-only",["administration"]="read-only",["analytics"]="read-only",["boards"]="read-only",["collection"]="none",["deployment"]="cloud",["errors"]="read-only",["host"]="analytics.example.com",["links"]="read-only",["pixels"]="read-only",["replays"]="read-only",["reports"]="read-only",["shares"]="read-only",["system"]="read-only",["teams"]="read-only",["websites"]="read-only"},auth_method="token",auth_config={key="fixture-umami-key"}},
 run=function(c)
  local expected={}
  for name in string.gmatch("websites.export administration.teams administration.users.list administration.users.twoFactor.status administration.websites boards.get boards.shares.list boards.list boards.dashboard.get websites.eventData.list websites.eventData.arraySeries websites.eventData.get websites.eventData.dateSeries websites.eventData.events websites.eventData.fields websites.eventData.numericSeries websites.eventData.numericStats websites.eventData.pivot websites.eventData.properties websites.eventData.propertySeries websites.eventData.stats websites.eventData.values system.heartbeat links.get links.shares.list links.list links.charts profile.get profile.apiKeys.list profile.teams profile.websites pixels.get pixels.shares.list pixels.list pixels.charts websites.analytics.realtime system.telemetryScript websites.sessionData.arraySeries websites.sessionData.dateSeries websites.sessionData.numericSeries websites.sessionData.numericStats websites.sessionData.pivot websites.sessionData.properties websites.sessionData.propertySeries websites.sessionData.stats websites.sessionData.values shares.get shares.bySlug profile.subscription teams.get teams.boards teams.links teams.pixels teams.members.get teams.members.list teams.websites teams.list profile.twoFactor.status websites.get websites.analytics.active websites.annotations.get websites.annotations.list websites.analytics.attribution websites.analytics.breakdown websites.analytics.dateRange websites.errors.event websites.errors.events websites.errors.issue websites.errors.issueValues websites.errors.stats websites.errors.values websites.errors.list websites.events.series websites.events.stats websites.events.list websites.analytics.expandedMetrics websites.funnels.get websites.funnels.stats websites.funnels.list websites.goals.get websites.goals.stats websites.goals.list websites.replays.heatmaps websites.analytics.journeys websites.analytics.metrics websites.analytics.pageviews websites.performance.chart websites.performance.metrics websites.performance.stats websites.replays.recorderConfig websites.replays.get websites.replays.isSaved websites.replays.list websites.analytics.retention websites.revenue.chart websites.revenue.metrics websites.revenue.sessions websites.revenue.stats websites.funnels.savedStats websites.goals.savedStats websites.replays.saved websites.segments.get websites.segments.list websites.sessions.get websites.sessions.activity websites.sessions.properties websites.sessions.replays websites.sessions.stats websites.sessions.list websites.sessions.weekly websites.shares.list websites.analytics.stats websites.analytics.utmMetrics websites.analytics.values websites.charts websites.list profile.verify","%S+") do expected[name]=true end
  local function inspect(node,prefix)
   for _,name in node.functions do
    local path=prefix..name
    assert(expected[path] and type(node[name])=="function","unexpected configured export: "..path)
    expected[path]=nil
   end
   for _,name in node.namespaces do
    assert(type(node[name])=="table","missing configured namespace: "..prefix..name)
    inspect(node[name],prefix..name..".")
   end
  end
  inspect(c,"")
  assert(next(expected)==nil,"missing configured export")
 end,
}
