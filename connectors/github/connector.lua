-- GitHub REST API, version 2026-03-10. Arguments and results keep GitHub's native field names.
type Options = {[string]: any}
type Endpoint = {method: string, path: string, query: {string}?, required: {string}?, body: boolean?, save: string?,
	diff: boolean?, auth: string?, about: string}

local API = "https://api.github.com"
local VERSION = "2026-03-10"
local JSON = "application/vnd.github+json"

-- Operations of GitHub's REST OpenAPI description, checked on 2026-10-16. Path {fields} are
-- required; listed query fields are taken from the options and the other fields form the JSON
-- body of POST, PATCH and PUT requests (and of DELETE requests marked body).
local endpoints: {[string]: Endpoint} = {
	getAuthenticatedUser = {method = "GET", path = "/user", about = "The connected account."},
	getUser = {method = "GET", path = "/users/{username}", about = "A user or organization profile."},
	listEmails = {method = "GET", path = "/user/emails", query = {"per_page", "page"}, about = "Your email addresses, including private ones."},
	getRateLimit = {method = "GET", path = "/rate_limit", about = "Remaining quota per resource (core, search, graphql...); reading it costs none."},
	listInstallations = {method = "GET", path = "/user/installations", query = {"per_page", "page"}, auth = "oauth",
		about = "Where Houston's app is installed, {total_count, installations}."},
	listInstallationRepos = {method = "GET", path = "/user/installations/{installation_id}/repositories", query = {"per_page", "page"}, auth = "oauth",
		about = "{total_count, repositories} you can access in one installation."},
	listMyOrgs = {method = "GET", path = "/user/orgs", query = {"per_page", "page"}, about = "Organizations you belong to."},
	getOrg = {method = "GET", path = "/orgs/{org}", about = ""},
	listOrgMembers = {method = "GET", path = "/orgs/{org}/members", query = {"filter", "role", "per_page", "page"}, about = "role: all, admin or member."},
	listOrgTeams = {method = "GET", path = "/orgs/{org}/teams", query = {"team_type", "per_page", "page"}, about = ""},
	listTeamMembers = {method = "GET", path = "/orgs/{org}/teams/{team_slug}/members", query = {"role", "per_page", "page"}, about = ""},

	listMyRepos = {method = "GET", path = "/user/repos", query = {"visibility", "affiliation", "type", "sort", "direction", "per_page", "page", "since", "before"},
		about = "Repositories you can access. affiliation: owner,collaborator,organization_member."},
	listUserRepos = {method = "GET", path = "/users/{username}/repos", query = {"type", "sort", "direction", "per_page", "page"}, about = "A user's public repositories."},
	listOrgRepos = {method = "GET", path = "/orgs/{org}/repos", query = {"type", "sort", "direction", "per_page", "page"}, about = ""},
	getRepo = {method = "GET", path = "/repos/{owner}/{repo}", about = "A repository, including default_branch and permissions."},
	createRepo = {method = "POST", path = "/user/repos", required = {"name"}, about = "Body {name, description?, private?, auto_init?, ...}."},
	createOrgRepo = {method = "POST", path = "/orgs/{org}/repos", required = {"name"}, about = "Body {name, description?, visibility?, auto_init?, ...}."},
	createFork = {method = "POST", path = "/repos/{owner}/{repo}/forks", about = "Body {organization?, name?, default_branch_only?}. Forking is asynchronous."},
	listForks = {method = "GET", path = "/repos/{owner}/{repo}/forks", query = {"sort", "per_page", "page"}, about = ""},
	listLanguages = {method = "GET", path = "/repos/{owner}/{repo}/languages", about = "Bytes of code per language."},
	getTopics = {method = "GET", path = "/repos/{owner}/{repo}/topics", query = {"per_page", "page"}, about = "{names}."},
	listContributors = {method = "GET", path = "/repos/{owner}/{repo}/contributors", query = {"anon", "per_page", "page"}, about = "Contributors by commit count."},
	listTags = {method = "GET", path = "/repos/{owner}/{repo}/tags", query = {"per_page", "page"}, about = "Tags with their commit SHAs."},
	listCollaborators = {method = "GET", path = "/repos/{owner}/{repo}/collaborators", query = {"affiliation", "permission", "per_page", "page"},
		about = "Collaborators; needs push access."},

	getReadme = {method = "GET", path = "/repos/{owner}/{repo}/readme", query = {"ref"}, about = "The README, base64 in content."},
	getContent = {method = "GET", path = "/repos/{owner}/{repo}/contents/{path}", query = {"ref"}, save = "application/vnd.github.raw+json",
		about = "A directory listing, or a file with base64 content up to 1 MB. save_as saves raw bytes (up to 100 MB). List the root with getTree."},
	putFile = {method = "PUT", path = "/repos/{owner}/{repo}/contents/{path}", required = {"message", "content"},
		about = "Body {message, content (base64), sha (required to replace a file), branch?, committer?}. Commits one file."},
	deleteFile = {method = "DELETE", path = "/repos/{owner}/{repo}/contents/{path}", required = {"message", "sha"}, body = true,
		about = "Body {message, sha, branch?}. Commits the deletion."},
	downloadTarball = {method = "GET", path = "/repos/{owner}/{repo}/tarball/{ref}", required = {"save_as"}, save = JSON, about = "Saves a .tar.gz archive of ref."},
	downloadZipball = {method = "GET", path = "/repos/{owner}/{repo}/zipball/{ref}", required = {"save_as"}, save = JSON, about = "Saves a .zip archive of ref."},

	listBranches = {method = "GET", path = "/repos/{owner}/{repo}/branches", query = {"protected", "per_page", "page"}, about = "Branches with head SHAs."},
	getBranch = {method = "GET", path = "/repos/{owner}/{repo}/branches/{branch}", about = "A branch and its head commit."},
	renameBranch = {method = "POST", path = "/repos/{owner}/{repo}/branches/{branch}/rename", required = {"new_name"}, about = "Body {new_name}. Updates open pull requests."},
	mergeUpstream = {method = "POST", path = "/repos/{owner}/{repo}/merge-upstream", required = {"branch"}, about = "Body {branch}. Syncs a fork branch with its upstream."},
	mergeBranch = {method = "POST", path = "/repos/{owner}/{repo}/merges", required = {"base", "head"},
		about = "Body {base, head, commit_message?}. Merges head into base; 204 when already merged."},

	listCommits = {method = "GET", path = "/repos/{owner}/{repo}/commits", query = {"sha", "path", "author", "committer", "since", "until", "per_page", "page"},
		about = "Commits, newest first. sha is a branch or SHA to start from."},
	getCommit = {method = "GET", path = "/repos/{owner}/{repo}/commits/{ref}", query = {"page", "per_page"}, diff = true,
		about = "A commit with its changed files (paged after 300 files)."},
	compareCommits = {method = "GET", path = "/repos/{owner}/{repo}/compare/{basehead}", query = {"page", "per_page"}, diff = true,
		about = "basehead is 'base...head'. Commits, files and ahead/behind counts."},
	getCombinedStatus = {method = "GET", path = "/repos/{owner}/{repo}/commits/{ref}/status", query = {"per_page", "page"},
		about = "Combined commit status: state is success, pending or failure."},
	listCommitStatuses = {method = "GET", path = "/repos/{owner}/{repo}/commits/{ref}/statuses", query = {"per_page", "page"}, about = ""},
	createCommitStatus = {method = "POST", path = "/repos/{owner}/{repo}/statuses/{sha}", required = {"state"},
		about = "Body {state (error, failure, pending or success), target_url?, description?, context?}."},
	listPullsForCommit = {method = "GET", path = "/repos/{owner}/{repo}/commits/{commit_sha}/pulls", query = {"per_page", "page"},
		about = "Pull requests containing a commit."},
	listCheckRuns = {method = "GET", path = "/repos/{owner}/{repo}/commits/{ref}/check-runs", query = {"check_name", "status", "filter", "app_id", "per_page", "page"},
		about = "CI check runs for a ref, {total_count, check_runs}."},
	listCheckSuites = {method = "GET", path = "/repos/{owner}/{repo}/commits/{ref}/check-suites", query = {"app_id", "check_name", "per_page", "page"},
		about = "{total_count, check_suites}."},
	getCheckRun = {method = "GET", path = "/repos/{owner}/{repo}/check-runs/{check_run_id}", about = "A check run with its output summary."},
	listCheckRunAnnotations = {method = "GET", path = "/repos/{owner}/{repo}/check-runs/{check_run_id}/annotations", query = {"per_page", "page"},
		about = "Annotations: file, line and message."},

	getRef = {method = "GET", path = "/repos/{owner}/{repo}/git/ref/{ref}", about = "ref is 'heads/<branch>' or 'tags/<tag>'."},
	listMatchingRefs = {method = "GET", path = "/repos/{owner}/{repo}/git/matching-refs/{ref}", about = "Refs starting with ref, such as 'heads/feature'."},
	createRef = {method = "POST", path = "/repos/{owner}/{repo}/git/refs", required = {"ref", "sha"},
		about = "Body {ref ('refs/heads/<branch>'), sha}. Creates a branch or tag ref."},
	updateRef = {method = "PATCH", path = "/repos/{owner}/{repo}/git/refs/{ref}", required = {"sha"},
		about = "ref is 'heads/<branch>'. Body {sha, force?}. Moves a branch."},
	deleteRef = {method = "DELETE", path = "/repos/{owner}/{repo}/git/refs/{ref}", about = "ref is 'heads/<branch>' or 'tags/<tag>'. Deletes a branch or tag."},
	getTree = {method = "GET", path = "/repos/{owner}/{repo}/git/trees/{tree_sha}", query = {"recursive"},
		about = "recursive=true lists every path; truncated is true past 100,000 entries or 7 MB. Large recursive trees can exceed the 8 MiB result limit."},
	createTree = {method = "POST", path = "/repos/{owner}/{repo}/git/trees", required = {"tree"},
		about = "Body {tree={{path, mode, type, sha or content}}, base_tree?}."},
	getBlob = {method = "GET", path = "/repos/{owner}/{repo}/git/blobs/{file_sha}", save = "application/vnd.github.raw+json",
		about = "A blob, base64 in content; save_as saves its raw bytes (up to 100 MB)."},
	createBlob = {method = "POST", path = "/repos/{owner}/{repo}/git/blobs", required = {"content"}, about = "Body {content, encoding? ('utf-8' or 'base64')}."},
	getGitCommit = {method = "GET", path = "/repos/{owner}/{repo}/git/commits/{commit_sha}", about = "A commit object with its tree and parents."},
	createGitCommit = {method = "POST", path = "/repos/{owner}/{repo}/git/commits", required = {"message", "tree"},
		about = "Body {message, tree, parents, author?}. Then updateRef moves the branch."},

	listIssuesAssigned = {method = "GET", path = "/issues", query = {"filter", "state", "labels", "sort", "direction", "since", "collab", "orgs", "owned", "pulls", "per_page", "page"},
		about = "Issues and pull requests assigned to you everywhere. filter: assigned, created, mentioned, subscribed or all."},
	listIssues = {method = "GET", path = "/repos/{owner}/{repo}/issues",
		query = {"milestone", "state", "assignee", "type", "creator", "mentioned", "issue_field_values", "labels", "sort", "direction", "since", "per_page", "page"},
		about = "Issues and pull requests (with pull_request). state: open, closed or all; labels comma-separated."},
	getIssue = {method = "GET", path = "/repos/{owner}/{repo}/issues/{issue_number}", about = "An issue or pull request."},
	createIssue = {method = "POST", path = "/repos/{owner}/{repo}/issues", required = {"title"}, about = "Body {title, body?, assignees?, labels?, milestone?, type?}."},
	updateIssue = {method = "PATCH", path = "/repos/{owner}/{repo}/issues/{issue_number}",
		about = "Body: fields to change, such as title, body, state ('closed'), state_reason, labels or assignees."},
	listIssueComments = {method = "GET", path = "/repos/{owner}/{repo}/issues/{issue_number}/comments", query = {"since", "per_page", "page"},
		about = "Conversation comments, oldest first."},
	createIssueComment = {method = "POST", path = "/repos/{owner}/{repo}/issues/{issue_number}/comments", required = {"body"},
		about = "Body {body}. Also comments on pull requests."},
	updateIssueComment = {method = "PATCH", path = "/repos/{owner}/{repo}/issues/comments/{comment_id}", required = {"body"}, about = "Body {body}."},
	deleteIssueComment = {method = "DELETE", path = "/repos/{owner}/{repo}/issues/comments/{comment_id}", about = ""},
	listIssueTimeline = {method = "GET", path = "/repos/{owner}/{repo}/issues/{issue_number}/timeline", query = {"exclude", "per_page", "page"},
		about = "Comments, labels, references and other events."},
	addLabels = {method = "POST", path = "/repos/{owner}/{repo}/issues/{issue_number}/labels", required = {"labels"}, about = "Body {labels={names}}."},
	setLabels = {method = "PUT", path = "/repos/{owner}/{repo}/issues/{issue_number}/labels", required = {"labels"},
		about = "Body {labels={names}}; json.decode('[]') removes all."},
	removeLabel = {method = "DELETE", path = "/repos/{owner}/{repo}/issues/{issue_number}/labels/{name}", about = "Returns the remaining labels."},
	addAssignees = {method = "POST", path = "/repos/{owner}/{repo}/issues/{issue_number}/assignees", required = {"assignees"}, about = "Body {assignees={logins}}."},
	removeAssignees = {method = "DELETE", path = "/repos/{owner}/{repo}/issues/{issue_number}/assignees", required = {"assignees"}, body = true,
		about = "Body {assignees={logins}}."},
	listAssignees = {method = "GET", path = "/repos/{owner}/{repo}/assignees", query = {"per_page", "page"}, about = ""},
	createIssueReaction = {method = "POST", path = "/repos/{owner}/{repo}/issues/{issue_number}/reactions", required = {"content"},
		about = "Body {content}: +1, -1, laugh, confused, heart, hooray, rocket or eyes."},
	listSubIssues = {method = "GET", path = "/repos/{owner}/{repo}/issues/{issue_number}/sub_issues", query = {"per_page", "page"}, about = ""},

	listLabels = {method = "GET", path = "/repos/{owner}/{repo}/labels", query = {"per_page", "page"}, about = ""},
	createLabel = {method = "POST", path = "/repos/{owner}/{repo}/labels", required = {"name"}, about = "Body {name, color? (hex without #), description?}."},
	updateLabel = {method = "PATCH", path = "/repos/{owner}/{repo}/labels/{name}", about = "Body {new_name?, color?, description?}."},
	deleteLabel = {method = "DELETE", path = "/repos/{owner}/{repo}/labels/{name}", about = ""},
	listMilestones = {method = "GET", path = "/repos/{owner}/{repo}/milestones", query = {"state", "sort", "direction", "per_page", "page"}, about = ""},
	getMilestone = {method = "GET", path = "/repos/{owner}/{repo}/milestones/{milestone_number}", about = ""},
	createMilestone = {method = "POST", path = "/repos/{owner}/{repo}/milestones", required = {"title"}, about = "Body {title, state?, description?, due_on?}."},
	updateMilestone = {method = "PATCH", path = "/repos/{owner}/{repo}/milestones/{milestone_number}", about = ""},
	deleteMilestone = {method = "DELETE", path = "/repos/{owner}/{repo}/milestones/{milestone_number}", about = ""},

	listPulls = {method = "GET", path = "/repos/{owner}/{repo}/pulls", query = {"state", "head", "base", "sort", "direction", "per_page", "page"},
		about = "Pull requests. head is 'owner:branch'."},
	getPull = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}", diff = true, about = "A pull request with mergeable state and counts."},
	createPull = {method = "POST", path = "/repos/{owner}/{repo}/pulls", required = {"head", "base"},
		about = "Body {head, base, title or issue, body?, draft?, maintainer_can_modify?}."},
	updatePull = {method = "PATCH", path = "/repos/{owner}/{repo}/pulls/{pull_number}", about = "Body: title, body, state, base or maintainer_can_modify."},
	mergePull = {method = "PUT", path = "/repos/{owner}/{repo}/pulls/{pull_number}/merge",
		about = "Body {merge_method? (merge, squash or rebase), commit_title?, commit_message?, sha?}. sha must match the head to merge."},
	updatePullBranch = {method = "PUT", path = "/repos/{owner}/{repo}/pulls/{pull_number}/update-branch",
		about = "Body {expected_head_sha?}. Merges the base into the head branch, asynchronously."},
	listPullFiles = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}/files", query = {"per_page", "page"},
		about = "Changed files with patches; at most 3,000 files."},
	listPullCommits = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}/commits", query = {"per_page", "page"}, about = "At most 250 commits."},
	listPullReviews = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}/reviews", query = {"per_page", "page"}, about = "Reviews, oldest first."},
	createPullReview = {method = "POST", path = "/repos/{owner}/{repo}/pulls/{pull_number}/reviews",
		about = "Body {event? (APPROVE, REQUEST_CHANGES or COMMENT; omit for a pending review), body?, commit_id?, comments?={{path, line, side?, body}}}."},
	submitPullReview = {method = "POST", path = "/repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/events", required = {"event"},
		about = "Body {event, body?}. Submits a pending review."},
	dismissPullReview = {method = "PUT", path = "/repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/dismissals", required = {"message"},
		about = "Body {message}. Needs admin or a branch protection bypass."},
	deletePendingReview = {method = "DELETE", path = "/repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}", about = "Deletes an unsubmitted review."},
	listPullReviewComments = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}/comments", query = {"sort", "direction", "since", "per_page", "page"},
		about = "Line comments on the diff."},
	createPullReviewComment = {method = "POST", path = "/repos/{owner}/{repo}/pulls/{pull_number}/comments", required = {"body", "commit_id", "path"},
		about = "Body {body, commit_id, path, line, side?, start_line?, subject_type?}."},
	replyToReviewComment = {method = "POST", path = "/repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies", required = {"body"},
		about = "Body {body}. comment_id is a top-level review comment."},
	listRequestedReviewers = {method = "GET", path = "/repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers", about = "{users, teams}."},
	requestReviewers = {method = "POST", path = "/repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers",
		about = "Body {reviewers?={logins}, team_reviewers?={slugs}}."},
	removeRequestedReviewers = {method = "DELETE", path = "/repos/{owner}/{repo}/pulls/{pull_number}/requested_reviewers", required = {"reviewers"}, body = true,
		about = "Body {reviewers={logins}, team_reviewers?}."},

	listReleases = {method = "GET", path = "/repos/{owner}/{repo}/releases", query = {"per_page", "page"}, about = "Releases, including drafts with push access."},
	getRelease = {method = "GET", path = "/repos/{owner}/{repo}/releases/{release_id}", about = "A release with its assets."},
	getLatestRelease = {method = "GET", path = "/repos/{owner}/{repo}/releases/latest", about = "The latest published full release."},
	getReleaseByTag = {method = "GET", path = "/repos/{owner}/{repo}/releases/tags/{tag}", about = "A published release by tag name."},
	createRelease = {method = "POST", path = "/repos/{owner}/{repo}/releases", required = {"tag_name"},
		about = "Body {tag_name, target_commitish?, name?, body?, draft?, prerelease?, generate_release_notes?, make_latest?}. Publishing notifies watchers."},
	updateRelease = {method = "PATCH", path = "/repos/{owner}/{repo}/releases/{release_id}", about = "Body: fields to change; draft=false publishes."},
	deleteRelease = {method = "DELETE", path = "/repos/{owner}/{repo}/releases/{release_id}", about = "Deletes a release, not its tag."},
	generateReleaseNotes = {method = "POST", path = "/repos/{owner}/{repo}/releases/generate-notes", required = {"tag_name"},
		about = "Body {tag_name, previous_tag_name?, target_commitish?}. Returns {name, body} and saves nothing."},
	listReleaseAssets = {method = "GET", path = "/repos/{owner}/{repo}/releases/{release_id}/assets", query = {"per_page", "page"}, about = ""},
	getReleaseAsset = {method = "GET", path = "/repos/{owner}/{repo}/releases/assets/{asset_id}", save = "application/octet-stream",
		about = "Asset metadata; save_as saves the asset's bytes as a session file."},
	deleteReleaseAsset = {method = "DELETE", path = "/repos/{owner}/{repo}/releases/assets/{asset_id}", about = ""},

	listWorkflows = {method = "GET", path = "/repos/{owner}/{repo}/actions/workflows", query = {"per_page", "page"}, about = "{total_count, workflows}."},
	getWorkflow = {method = "GET", path = "/repos/{owner}/{repo}/actions/workflows/{workflow_id}", about = "workflow_id is the ID or file name, such as 'ci.yml'."},
	dispatchWorkflow = {method = "POST", path = "/repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches", required = {"ref"},
		about = "Body {ref, inputs?}. Starts a workflow_dispatch run and returns its run ID and URLs."},
	listWorkflowRuns = {method = "GET", path = "/repos/{owner}/{repo}/actions/runs",
		query = {"actor", "branch", "event", "status", "created", "exclude_pull_requests", "check_suite_id", "head_sha", "per_page", "page"},
		about = "{total_count, workflow_runs}, newest first."},
	listRunsForWorkflow = {method = "GET", path = "/repos/{owner}/{repo}/actions/workflows/{workflow_id}/runs",
		query = {"actor", "branch", "event", "status", "created", "exclude_pull_requests", "check_suite_id", "head_sha", "per_page", "page"},
		about = "Runs of one workflow, as listWorkflowRuns."},
	getWorkflowRun = {method = "GET", path = "/repos/{owner}/{repo}/actions/runs/{run_id}", query = {"exclude_pull_requests"}, about = "A run with status and conclusion."},
	cancelWorkflowRun = {method = "POST", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/cancel", about = ""},
	rerunWorkflow = {method = "POST", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/rerun", about = "Body {enable_debug_logging?}. Reruns every job."},
	rerunFailedJobs = {method = "POST", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/rerun-failed-jobs", about = "Body {enable_debug_logging?}."},
	downloadRunLogs = {method = "GET", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/logs", required = {"save_as"}, save = JSON,
		about = "Saves a .zip of every job's logs."},
	listRunJobs = {method = "GET", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/jobs", query = {"filter", "per_page", "page"},
		about = "{total_count, jobs} with steps and conclusions. filter: latest or all."},
	getJob = {method = "GET", path = "/repos/{owner}/{repo}/actions/jobs/{job_id}", about = "A job with its steps."},
	downloadJobLogs = {method = "GET", path = "/repos/{owner}/{repo}/actions/jobs/{job_id}/logs", required = {"save_as"}, save = JSON,
		about = "Saves a job's plain-text log; search it with fs.grep."},
	listArtifacts = {method = "GET", path = "/repos/{owner}/{repo}/actions/artifacts", query = {"name", "per_page", "page"}, about = "{total_count, artifacts}."},
	listRunArtifacts = {method = "GET", path = "/repos/{owner}/{repo}/actions/runs/{run_id}/artifacts", query = {"name", "direction", "per_page", "page"},
		about = ""},
	downloadArtifact = {method = "GET", path = "/repos/{owner}/{repo}/actions/artifacts/{artifact_id}/{archive_format}", required = {"save_as"}, save = JSON,
		about = "archive_format is 'zip'. Saves the artifact's .zip."},

	searchRepos = {method = "GET", path = "/search/repositories", query = {"q", "sort", "order", "per_page", "page"}, required = {"q"},
		about = "q such as 'houston language:go stars:>10'."},
	searchCode = {method = "GET", path = "/search/code", query = {"q", "sort", "order", "per_page", "page"}, required = {"q"},
		about = "q such as 'fetchUser repo:octo/app language:ts'; default branches only. 10 requests per minute."},
	searchIssues = {method = "GET", path = "/search/issues", query = {"q", "sort", "order", "per_page", "page", "advanced_search", "search_type"}, required = {"q"},
		about = "Issues and pull requests; q such as 'repo:octo/app is:pr is:open review-requested:@me'."},
	searchCommits = {method = "GET", path = "/search/commits", query = {"q", "sort", "order", "per_page", "page"}, required = {"q"}, about = "q such as 'repo:octo/app fix'."},
	searchUsers = {method = "GET", path = "/search/users", query = {"q", "sort", "order", "per_page", "page"}, required = {"q"}, about = ""},

	listGists = {method = "GET", path = "/gists", query = {"since", "per_page", "page"}, about = ""},
	listUserGists = {method = "GET", path = "/users/{username}/gists", query = {"since", "per_page", "page"}, about = ""},
	getGist = {method = "GET", path = "/gists/{gist_id}", about = "A gist with file contents (truncated past 1 MB; see raw_url)."},
	createGist = {method = "POST", path = "/gists", required = {"files"}, about = "Body {files={['name.md']={content}}, description?, public? (default false)}."},
	updateGist = {method = "PATCH", path = "/gists/{gist_id}", about = "Body {description?, files?}; a file set to json.decode('null') is deleted."},
	deleteGist = {method = "DELETE", path = "/gists/{gist_id}", about = ""},

	listNotifications = {method = "GET", path = "/notifications", query = {"all", "participating", "since", "before", "per_page", "page"}, auth = "token",
		about = "Unread notification threads; all=true includes read ones."},
	markNotificationsRead = {method = "PUT", path = "/notifications", auth = "token", about = "Body {last_read_at?, read?}."},
	markThreadRead = {method = "PATCH", path = "/notifications/threads/{thread_id}", auth = "token", about = ""},
	markThreadDone = {method = "DELETE", path = "/notifications/threads/{thread_id}", auth = "token", about = "Marks a thread as done."},
}
local NULL = json.decode("null")
local NONE: {string} = table.freeze({})

-- Branch, ref, path, tag, tree, compare and label values may contain slashes; GitHub accepts them encoded.
local OPAQUE = table.freeze({branch = true, ref = true, path = true, basehead = true, tag = true, name = true, tree_sha = true})
local DOWNLOAD_HOSTS = table.freeze({"codeload.github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com",
	"objects-origin.githubusercontent.com", "github-releases.githubusercontent.com"})

local function options(input: Options?): Options
	if input == nil then return {} end
	assert(type(input) == "table", "opts must be an object")
	for key in input do assert(type(key) == "string", "opts must have named fields") end
	return table.clone(input)
end

local function text(value: any, field: string): string
	assert(type(value) == "string" and value ~= "" and not string.find(value, "%c"), field .. " must be a nonempty string without control characters")
	return value
end

local function segment(value: any, field: string): string
	if string.match(field, "_number$") or (string.match(field, "_id$") and field ~= "workflow_id" and field ~= "gist_id") then
		local number = if type(value) == "string" and string.match(value, "^%d+$") then tonumber(value) else value
		assert(type(number) == "number" and number % 1 == 0 and number >= 1 and number < 2 ^ 53, field .. " must be a positive integer")
		return string.format("%d", number)
	end
	if OPAQUE[field] then
		-- Each part passes url.segment (no dot, backslash, percent or look-alike traversal), so the
		-- proxy's opaque check never has to refuse it; the slashes travel encoded.
		local parts: {string} = {}
		for _, part in string.split(text(value, field), "/") do
			local ok, encoded = pcall(url.segment, part)
			assert(ok, field .. " must be slash-separated names without empty, . or .. parts, backslashes or percent signs")
			table.insert(parts, encoded)
		end
		return table.concat(parts, "%2F")
	end
	-- workflow_id is a numeric ID or a file name.
	if type(value) == "number" and value % 1 == 0 and value >= 1 and value < 2 ^ 53 then value = string.format("%d", value) end
	local ok, result = pcall(url.segment, value, field)
	assert(ok, field .. " must be a GitHub name or SHA")
	return result
end

local function scalar(value: any, field: string): string
	local kind = type(value)
	assert(kind == "string" or kind == "boolean" or kind == "number", field .. " must be a string, boolean or number")
	return url.encode(value)
end

local function header(response: HttpResponse, name: string): string?
	local values = response.headers[name]
	return if values and values[1] then string.sub(values[1], 1, 200) else nil
end

-- GitHub errors are {message, documentation_url?, errors?: [{resource, field, code, message?}], status}.
-- Primary rate limits answer 403 or 429 with x-ratelimit-remaining 0; secondary ones may add
-- retry-after, and otherwise only say so in the message.
local function fail(name: string, response: HttpResponse): never
	local message = "GitHub HTTP " .. tostring(response.statusCode)
	local ok, value = pcall(json.decode, await(response.body:readPrefix(16 * 1024)))
	if ok and type(value) == "table" then
		if type(value.message) == "string" then message ..= ": " .. string.sub(value.message, 1, 600) end
		if type(value.errors) == "table" then message ..= " " .. string.sub(json.encode(value.errors), 1, 600) end
	end
	local retryAfter = header(response, "retry-after")
	local exhausted = header(response, "x-ratelimit-remaining") == "0"
	local secondary = string.find(message, "secondary rate limit", 1, true) ~= nil
	if retryAfter then message ..= "; retry after " .. retryAfter .. "s" end
	if exhausted then message ..= "; rate limit resets at " .. (header(response, "x-ratelimit-reset") or "?") .. " (Unix time)" end
	-- Renamed or transferred repositories redirect to /repositories/<id>, which no rule allows.
	local moved = header(response, "location")
	if moved and string.find(moved, "https://api.github.com/repositories/", 1, true) == 1 then
		message ..= "; the repository was renamed or transferred: use its new owner and name"
	end
	local accepted = header(response, "x-accepted-github-permissions")
	if accepted then message ..= "; needs permissions " .. accepted end
	local status = response.statusCode
	return houston.fail({operation = name, layer = "upstream", upstream_status = status,
		retryable = status == 429 or status >= 500 or (status == 403 and (exhausted or secondary or retryAfter ~= nil)), message = message})
end

-- Private file links carry a short-lived token usable outside Houston; keep the link, drop the token.
local function unsign(value: any)
	if type(value) ~= "table" then return end
	for key, child in value do
		if key == "download_url" and type(child) == "string" then
			value[key] = string.match(child, "^[^?]*")
		else
			unsign(child)
		end
	end
end

-- Writes answer 204 or 205 without a body; reads answer 204 for an empty list, such as an
-- empty repository's contributors.
local function decode(name: string, endpoint: Endpoint, response: HttpResponse): any
	if response.statusCode == 204 or response.statusCode == 205 then
		response.body:close()
		return if endpoint.method == "GET" then json.decode("[]") else {success = true}
	end
	local raw = await(response.body:readAll())
	local ok, value = pcall(json.decode, raw)
	if not ok or type(value) ~= "table" then
		return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = false,
			message = "GitHub returned invalid JSON"})
	end
	unsign(value)
	return value
end

local function allowedDownload(location: string): boolean
	local host = string.match(location, "^https://([%w%.%-]+)/")
	if host == nil then return false end
	host = string.lower(host)
	return table.find(DOWNLOAD_HOSTS, host) ~= nil or string.match(host, "^productionresultssa%d+%.blob%.core%.windows%.net$") ~= nil
		or string.match(host, "^[%w%-]+%.actions%.githubusercontent%.com$") ~= nil
end

-- Archives, assets and logs redirect to a signed URL, fetched without credentials.
local function save(name: string, first: HttpResponse, output: any, destination: string): any
	local response = first
	local location = first.headers.location
	local target = if location then location[1] else nil
	local kind = first.headers["content-type"]
	if first.statusCode >= 300 and first.statusCode < 400 and target then
		if string.find(target, "https://api.github.com/", 1, true) == 1 then fail(name, first) end
		first.body:close()
		if not allowedDownload(target) then
			return houston.fail({operation = name, layer = "upstream", upstream_status = first.statusCode, retryable = false,
				message = "GitHub redirected the download to an unexpected host"})
		end
		response = await(http.request({method = "GET", url = target, headers = {["User-Agent"] = {"Houston"}}}))
		if response.statusCode ~= 200 then
			-- Signed links expire within minutes; a new call fetches a fresh one.
			response.body:close()
			return houston.fail({operation = name, layer = "upstream", upstream_status = response.statusCode, retryable = true,
				message = "The signed download link failed with HTTP " .. tostring(response.statusCode) .. "; call again for a fresh link"})
		end
	elseif first.statusCode == 200 and kind and string.find(kind[1], "application/json", 1, true) == 1 then
		-- Directories and submodules answer with JSON even when raw bytes are requested.
		first.body:close()
		return houston.fail({operation = name, layer = "upstream", upstream_status = 200, retryable = false,
			message = "The path is a directory or submodule; call getContent without save_as to inspect it"})
	end
	if response.statusCode ~= 200 then fail(name, response) end
	output:write(response.body)
	await(output:close())
	return {path = destination, size = await(fs.stat(destination)).size, url = await(fs.signedGetUrl(destination))}
end

local function request(name: string, endpoint: Endpoint, input: Options?): any
	local args = options(input)
	local path = string.gsub(endpoint.path, "{([%w_]+)}", function(field: string)
		local value = segment(args[field], field)
		args[field] = nil
		return value
	end)
	for _, field in endpoint.required or NONE do
		assert(args[field] ~= nil and args[field] ~= NULL, field .. " is required")
	end
	local headers: HttpHeaders = {Accept = {JSON}, ["X-GitHub-Api-Version"] = {VERSION}, ["User-Agent"] = {"Houston"}}
	local destination: string? = nil
	if endpoint.save and args.save_as ~= nil then
		destination = text(args.save_as, "save_as")
		headers.Accept = {endpoint.save}
		args.save_as = nil
	end
	local format = if endpoint.diff then args.format else nil
	if format ~= nil then
		assert(format == "diff" or format == "patch", "format must be 'diff' or 'patch'")
		headers.Accept = {"application/vnd.github." .. format}
		args.format = nil
	end
	-- getTree recurses for any recursive value, false included.
	if name == "getTree" and args.recursive ~= nil then
		assert(type(args.recursive) == "boolean", "recursive must be true or false")
		if not args.recursive then args.recursive = nil end
	end
	local query: {string} = {}
	for _, field in endpoint.query or NONE do
		if args[field] ~= nil then table.insert(query, field .. "=" .. scalar(args[field], field)) end
		args[field] = nil
	end
	if #query > 0 then path ..= "?" .. table.concat(query, "&") end
	local body: string? = nil
	if endpoint.body or endpoint.method == "POST" or endpoint.method == "PATCH" or endpoint.method == "PUT" then
		headers["Content-Type"] = {"application/json"}
		body = json.encode(args)
		args = {}
	end
	local unknown = next(args)
	assert(unknown == nil, name .. " has no option " .. tostring(unknown))
	local call: HttpRequest = {url = API .. path, method = endpoint.method, headers = headers, body = body}
	if destination == nil then
		local response = await(http.request(call))
		if response.statusCode < 200 or response.statusCode >= 300 then fail(name, response) end
		if format then return await(response.body:readAll()) end
		return decode(name, endpoint, response)
	end
	-- Open the destination before the request, so a bad path never reaches GitHub; close it on failure.
	local output = await(fs.open(destination, "w"))
	local ok, result = pcall(function(): any return save(name, await(http.request(call)), output, destination) end)
	if not ok then
		pcall(function() await(output:close()) end)
		error(result, 0)
	end
	return result
end

local exports: {[string]: any} = {}
for name, endpoint in endpoints do
	local enabled = endpoint.method == "GET" or config.access == "read-write"
	if endpoint.auth and endpoint.auth ~= auth.method then enabled = false end
	if enabled then exports[name] = function(args: Options?): any return request(name, endpoint, args) end end
end

local REPO = "/repos/{owner}/{repo}"

-- name({path fields, query fields?}) built from the endpoint itself. Repository routes leave
-- owner and repo implicit, page? stands for per_page and page, and Body {...} lists body fields.
local function signature(endpoint: Endpoint): string
	local fields: {string} = {}
	for field in string.gmatch(endpoint.path, "{([%w_]+)}") do
		if field ~= "owner" and field ~= "repo" then table.insert(fields, field) end
	end
	local required = endpoint.required or NONE
	for _, field in endpoint.query or NONE do
		if field ~= "per_page" then table.insert(fields, if table.find(required, field) then field else field .. "?") end
	end
	if endpoint.save then table.insert(fields, if table.find(required, "save_as") then "save_as" else "save_as?") end
	if endpoint.diff then table.insert(fields, "format?") end
	return "({" .. table.concat(fields, ", ") .. "})"
end

exports.help = function(): string
	local lines = {
		"GitHub REST API " .. VERSION .. ". Each function takes one options object with GitHub's snake_case names (? marks optional); writes also take the JSON body fields listed after Body. Results are GitHub's JSON unchanged; write replies without a body return {success=true}. Connector calls return completed values: use them directly, without await. In bodies, json.decode('[]') is an empty array and json.decode('null') clears a field.",
		"Start with github.getAuthenticatedUser().login, github.listMyRepos({sort='pushed', per_page=20}) or github.searchIssues({q='is:pr is:open author:@me'}). branch, ref, path, tag, tree_sha, basehead and label name may contain slashes (ref='heads/feature/x', path='src/main.go'), but not percent signs or backslashes.",
		"Lists return one page: page? means per_page (1..100, default 30) and page (from 1); a shorter page is the last. JSON and text results over 8 MiB fail; use save_as or smaller pages. Search returns {total_count, incomplete_results, items}: at most 1,000 results and 30 requests per minute (searchCode 10).",
		"Files: getContent returns base64 content; save_as='name' saves raw bytes as a session file instead. download_url links lose their private-repository token, so fetch private files with save_as. save_as functions return {path, size, url} and overwrite that session file, even when the download fails; search large logs with fs.grep. getCommit, compareCommits and getPull take format='diff' or 'patch' and return that text, without paging. To commit several files, chain createBlob, createTree, createGitCommit and updateRef.",
		"Access: GitHub enforces the token's permissions and repository selection; Connect with GitHub reaches public data and repositories where Houston's GitHub App is installed. A 403 or 404 may mean missing access; errors give GitHub's message, needed permissions and rate-limit resets. Read-only connections omit writes. Notifications need a classic token and installation lists Connect with GitHub; check runs and suites need a classic token or Connect with GitHub.",
		"Writes can notify people and trigger workflows. No automatic retries: after a timeout or 5xx, read the resource again before repeating a write. Repository deletion, settings administration, secrets, webhooks, deploy keys and GraphQL are not exposed.",
	}
	local names: {string} = {}
	for name in exports do if name ~= "help" then table.insert(names, name) end end
	table.sort(names)
	local repository: {string} = {"Repository functions also take owner and repo, such as owner='octocat', repo='Hello-World'; ... stands for " .. REPO .. ":"}
	for _, name in names do
		local endpoint = endpoints[name]
		local inRepo = string.sub(endpoint.path, 1, #REPO) == REPO
		local route = if inRepo then "..." .. string.sub(endpoint.path, #REPO + 1) else endpoint.path
		local about = if endpoint.about == "" then "" else endpoint.about .. " "
		table.insert(if inRepo then repository else lines, name .. signature(endpoint) .. ": " .. about .. endpoint.method .. " " .. route)
	end
	table.move(repository, 1, #repository, #lines + 1, lines)
	return table.concat(lines, "\n")
end
return exports
