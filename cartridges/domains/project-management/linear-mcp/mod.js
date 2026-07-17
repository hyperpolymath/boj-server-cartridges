// SPDX-License-Identifier: MPL-2.0
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// linear-mcp/mod.js — Linear cartridge implementation (GraphQL).
//
// Covers Linear and its related services:
//   - Issues      : list, get, create, update, archive, search, assign, prioritise, move
//   - Comments    : list, create
//   - Projects    : list, get, create, update, milestones
//   - Teams       : list, get, cycles, labels, workflow states
//   - Users       : list, viewer ("whoami")
//   - Documents   : list, get
//   - Initiatives : list
//   - Attachments : create (link a PR/URL to an issue)
//
// Auth: LINEAR_API_KEY (required). Linear personal API keys (lin_api_...) are
// sent RAW in the Authorization header — the "Bearer" prefix is only correct
// for OAuth2 access tokens. Sending "Bearer lin_api_..." fails with 401.
// https://linear.app/developers/graphql
//
// Rate limits: Linear reports exhaustion as HTTP *400* carrying a GraphQL error
// with extensions.code === "RATELIMITED" — NOT HTTP 429. Code that only checks
// for 429 silently misreads a rate-limit as a generic bad request.
// https://linear.app/developers/rate-limiting
//
// Usage: import { handleTool } from "./mod.js";

const API_URL = "https://api.linear.app/graphql";
const TIMEOUT_MS = 20_000;
const DEFAULT_PAGE = 50;
const MAX_PAGE = 250;

// ---------------------------------------------------------------------------
// Auth — credential comes from vault-mcp in production, env var locally.
// ---------------------------------------------------------------------------

function getKey() {
  const key = typeof Deno !== "undefined"
    ? Deno.env.get("LINEAR_API_KEY")
    : globalThis.process?.env?.LINEAR_API_KEY;
  return key || null;
}

/// Personal API keys go in Authorization unprefixed; OAuth2 tokens need "Bearer".
function authValue(key) {
  return key.startsWith("lin_api_") ? key : `Bearer ${key}`;
}

// ---------------------------------------------------------------------------
// GraphQL transport
// ---------------------------------------------------------------------------

function rateLimitHeaders(h) {
  const out = {};
  for (
    const k of [
      "x-ratelimit-requests-remaining",
      "x-ratelimit-requests-reset",
      "x-ratelimit-complexity-remaining",
      "x-complexity",
    ]
  ) {
    const v = h.get(k);
    if (v !== null) out[k] = v;
  }
  return out;
}

async function graphql(query, variables) {
  const key = getKey();
  if (!key) {
    return { status: 401, error: "LINEAR_API_KEY not set (source: vault-mcp)." };
  }

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);

  let response;
  try {
    response = await fetch(API_URL, {
      method: "POST",
      headers: {
        "Authorization": authValue(key),
        "Content-Type": "application/json",
        "User-Agent": "boj-server/linear-mcp/0.2.0",
      },
      body: JSON.stringify({ query, variables: variables ?? {} }),
      signal: ctrl.signal,
    });
  } catch (e) {
    if (e.name === "AbortError") {
      return { status: 504, error: `Linear API timed out after ${TIMEOUT_MS}ms.` };
    }
    return { status: 503, error: `Linear API unreachable: ${e.message}` };
  } finally {
    clearTimeout(timer);
  }

  const limits = rateLimitHeaders(response.headers);
  const body = await response.json().catch(() => null);

  if (body === null) {
    return { status: response.status, error: `Non-JSON response (HTTP ${response.status}).`, limits };
  }

  const errors = Array.isArray(body.errors) ? body.errors : [];

  // Rate limiting arrives as HTTP 400 + extensions.code RATELIMITED, not 429.
  if (errors.some((e) => e?.extensions?.code === "RATELIMITED") || response.status === 429) {
    return { status: 429, error: "Linear rate limit exceeded.", rateLimited: true, limits };
  }

  if (response.status === 401 || response.status === 403) {
    return { status: response.status, error: "Linear rejected the API key.", limits };
  }

  if (errors.length > 0) {
    return {
      status: response.status === 200 ? 400 : response.status,
      error: errors.map((e) => e.message).join("; "),
      errors,
      limits,
    };
  }

  if (!response.ok) {
    return { status: response.status, error: `HTTP ${response.status}`, limits };
  }

  return { status: 200, data: body.data, limits };
}

// ---------------------------------------------------------------------------
// Shared selection sets
// ---------------------------------------------------------------------------

const ISSUE_FIELDS = `
  id
  identifier
  title
  description
  priority
  url
  createdAt
  updatedAt
  state { id name type }
  assignee { id name displayName }
  team { id key name }
  project { id name }
  labels { nodes { id name } }
`;

const PROJECT_FIELDS = `
  id
  name
  description
  state
  progress
  url
  startDate
  targetDate
  lead { id name }
  teams { nodes { id key name } }
`;

/// Linear's issue(id:) takes a UUID. Human identifiers ("ENG-123") have to be
/// resolved through a filter instead, so accept either form.
const IDENTIFIER_RE = /^[A-Za-z][A-Za-z0-9]*-\d+$/;

const ok = (data) => ({ status: 200, data });
const missing = (field) => ({ status: 400, error: `Missing required field: ${field}` });

// ---------------------------------------------------------------------------
// Tool dispatch
// ---------------------------------------------------------------------------

export async function handleTool(toolName, args) {
  const a = args ?? {};
  const limit = Math.min(Number(a.limit) || DEFAULT_PAGE, MAX_PAGE);

  switch (toolName) {
    // ── Issues ────────────────────────────────────────────────────────────

    case "linear_list_issues": {
      const filter = {};
      if (a.team_id) filter.team = { id: { eq: a.team_id } };
      if (a.project_id) filter.project = { id: { eq: a.project_id } };
      if (a.assignee_id) filter.assignee = { id: { eq: a.assignee_id } };
      if (a.state) filter.state = { name: { eqIgnoreCase: a.state } };

      const r = await graphql(
        `query ListIssues($first: Int!, $filter: IssueFilter) {
           issues(first: $first, filter: $filter) {
             nodes { ${ISSUE_FIELDS} }
             pageInfo { hasNextPage endCursor }
           }
         }`,
        { first: limit, filter: Object.keys(filter).length ? filter : undefined },
      );
      if (r.error) return r;
      const n = r.data.issues.nodes;
      return ok({ issues: n, count: n.length, pageInfo: r.data.issues.pageInfo });
    }

    case "linear_get_issue": {
      const id = a.issue_id;
      if (!id) return missing("issue_id");

      if (IDENTIFIER_RE.test(id)) {
        const [teamKey, num] = id.split("-");
        const r = await graphql(
          `query GetIssueByIdentifier($filter: IssueFilter) {
             issues(first: 1, filter: $filter) { nodes { ${ISSUE_FIELDS} } }
           }`,
          { filter: { team: { key: { eqIgnoreCase: teamKey } }, number: { eq: Number(num) } } },
        );
        if (r.error) return r;
        const issue = r.data.issues.nodes[0];
        if (!issue) return { status: 404, error: `Issue not found: ${id}` };
        return ok({ issue });
      }

      const r = await graphql(
        `query GetIssue($id: String!) { issue(id: $id) { ${ISSUE_FIELDS} } }`,
        { id },
      );
      if (r.error) return r;
      if (!r.data.issue) return { status: 404, error: `Issue not found: ${id}` };
      return ok({ issue: r.data.issue });
    }

    case "linear_create_issue": {
      if (!a.team_id) return missing("team_id");
      if (!a.title) return missing("title");

      const input = { teamId: a.team_id, title: a.title };
      if (a.description) input.description = a.description;
      if (a.priority !== undefined) input.priority = Number(a.priority);
      if (a.assignee_id) input.assigneeId = a.assignee_id;
      if (a.project_id) input.projectId = a.project_id;
      if (a.state_id) input.stateId = a.state_id;
      if (Array.isArray(a.label_ids)) input.labelIds = a.label_ids;

      const r = await graphql(
        `mutation CreateIssue($input: IssueCreateInput!) {
           issueCreate(input: $input) { success issue { ${ISSUE_FIELDS} } }
         }`,
        { input },
      );
      if (r.error) return r;
      return ok(r.data.issueCreate);
    }

    case "linear_update_issue": {
      if (!a.issue_id) return missing("issue_id");
      const input = a.fields && typeof a.fields === "object" ? { ...a.fields } : {};
      if (a.title) input.title = a.title;
      if (a.description) input.description = a.description;
      if (a.priority !== undefined) input.priority = Number(a.priority);
      if (a.state_id) input.stateId = a.state_id;
      if (Object.keys(input).length === 0) return { status: 400, error: "No fields to update." };
      return updateIssue(a.issue_id, input);
    }

    case "linear_assign_issue": {
      if (!a.issue_id) return missing("issue_id");
      if (!a.assignee_id) return missing("assignee_id");
      return updateIssue(a.issue_id, { assigneeId: a.assignee_id });
    }

    case "linear_set_priority": {
      if (!a.issue_id) return missing("issue_id");
      if (a.priority === undefined) return missing("priority");
      const p = Number(a.priority);
      if (!Number.isInteger(p) || p < 0 || p > 4) {
        return {
          status: 400,
          error: "priority must be 0 (none), 1 (urgent), 2 (high), 3 (medium) or 4 (low).",
        };
      }
      return updateIssue(a.issue_id, { priority: p });
    }

    case "linear_move_to_project": {
      if (!a.issue_id) return missing("issue_id");
      if (!a.project_id) return missing("project_id");
      return updateIssue(a.issue_id, { projectId: a.project_id });
    }

    case "linear_archive_issue": {
      if (!a.issue_id) return missing("issue_id");
      const r = await graphql(
        `mutation ArchiveIssue($id: String!) { issueArchive(id: $id) { success } }`,
        { id: a.issue_id },
      );
      if (r.error) return r;
      return ok(r.data.issueArchive);
    }

    case "linear_search_issues": {
      if (!a.query) return missing("query");
      // Filter-based search: stable across API versions, unlike the deprecated
      // issueSearch root field.
      const r = await graphql(
        `query SearchIssues($first: Int!, $filter: IssueFilter) {
           issues(first: $first, filter: $filter) { nodes { ${ISSUE_FIELDS} } }
         }`,
        {
          first: limit,
          filter: {
            or: [
              { title: { containsIgnoreCase: a.query } },
              { description: { containsIgnoreCase: a.query } },
            ],
          },
        },
      );
      if (r.error) return r;
      const n = r.data.issues.nodes;
      return ok({ matches: n, count: n.length });
    }

    // ── Comments ──────────────────────────────────────────────────────────

    case "linear_list_comments": {
      if (!a.issue_id) return missing("issue_id");
      const r = await graphql(
        `query ListComments($first: Int!, $filter: CommentFilter) {
           comments(first: $first, filter: $filter) {
             nodes { id body createdAt url user { id name displayName } }
           }
         }`,
        { first: limit, filter: { issue: { id: { eq: a.issue_id } } } },
      );
      if (r.error) return r;
      const n = r.data.comments.nodes;
      return ok({ comments: n, count: n.length });
    }

    case "linear_create_comment": {
      if (!a.issue_id) return missing("issue_id");
      if (!a.body) return missing("body");
      const r = await graphql(
        `mutation CreateComment($input: CommentCreateInput!) {
           commentCreate(input: $input) { success comment { id body url createdAt } }
         }`,
        { input: { issueId: a.issue_id, body: a.body } },
      );
      if (r.error) return r;
      return ok(r.data.commentCreate);
    }

    // ── Projects ──────────────────────────────────────────────────────────

    case "linear_list_projects": {
      const r = await graphql(
        `query ListProjects($first: Int!) {
           projects(first: $first) { nodes { ${PROJECT_FIELDS} } }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.projects.nodes;
      return ok({ projects: n, count: n.length });
    }

    case "linear_get_project": {
      if (!a.project_id) return missing("project_id");
      const r = await graphql(
        `query GetProject($id: String!) { project(id: $id) { ${PROJECT_FIELDS} } }`,
        { id: a.project_id },
      );
      if (r.error) return r;
      if (!r.data.project) return { status: 404, error: `Project not found: ${a.project_id}` };
      return ok({ project: r.data.project });
    }

    case "linear_create_project": {
      if (!a.name) return missing("name");
      if (!Array.isArray(a.team_ids) || a.team_ids.length === 0) return missing("team_ids");
      const input = { name: a.name, teamIds: a.team_ids };
      if (a.description) input.description = a.description;
      if (a.target_date) input.targetDate = a.target_date;
      if (a.lead_id) input.leadId = a.lead_id;
      const r = await graphql(
        `mutation CreateProject($input: ProjectCreateInput!) {
           projectCreate(input: $input) { success project { ${PROJECT_FIELDS} } }
         }`,
        { input },
      );
      if (r.error) return r;
      return ok(r.data.projectCreate);
    }

    case "linear_update_project": {
      if (!a.project_id) return missing("project_id");
      const input = a.fields && typeof a.fields === "object" ? { ...a.fields } : {};
      if (a.name) input.name = a.name;
      if (a.description) input.description = a.description;
      if (a.state) input.state = a.state;
      if (Object.keys(input).length === 0) return { status: 400, error: "No fields to update." };
      const r = await graphql(
        `mutation UpdateProject($id: String!, $input: ProjectUpdateInput!) {
           projectUpdate(id: $id, input: $input) { success project { ${PROJECT_FIELDS} } }
         }`,
        { id: a.project_id, input },
      );
      if (r.error) return r;
      return ok(r.data.projectUpdate);
    }

    case "linear_list_project_milestones": {
      if (!a.project_id) return missing("project_id");
      const r = await graphql(
        `query ProjectMilestones($id: String!) {
           project(id: $id) {
             id
             projectMilestones { nodes { id name description targetDate sortOrder } }
           }
         }`,
        { id: a.project_id },
      );
      if (r.error) return r;
      if (!r.data.project) return { status: 404, error: `Project not found: ${a.project_id}` };
      const n = r.data.project.projectMilestones.nodes;
      return ok({ milestones: n, count: n.length });
    }

    // ── Teams, cycles, labels, workflow states ────────────────────────────

    case "linear_list_teams": {
      const r = await graphql(
        `query ListTeams($first: Int!) {
           teams(first: $first) { nodes { id key name description private } }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.teams.nodes;
      return ok({ teams: n, count: n.length });
    }

    case "linear_get_team": {
      if (!a.team_id) return missing("team_id");
      const r = await graphql(
        `query GetTeam($id: String!) {
           team(id: $id) {
             id key name description private
             members { nodes { id name displayName email } }
           }
         }`,
        { id: a.team_id },
      );
      if (r.error) return r;
      if (!r.data.team) return { status: 404, error: `Team not found: ${a.team_id}` };
      return ok({ team: r.data.team });
    }

    case "linear_list_cycles": {
      const r = await graphql(
        `query ListCycles($first: Int!, $filter: CycleFilter) {
           cycles(first: $first, filter: $filter) {
             nodes { id number name startsAt endsAt progress completedAt team { id key } }
           }
         }`,
        { first: limit, filter: a.team_id ? { team: { id: { eq: a.team_id } } } : undefined },
      );
      if (r.error) return r;
      const n = r.data.cycles.nodes;
      return ok({ cycles: n, count: n.length });
    }

    case "linear_list_labels": {
      const r = await graphql(
        `query ListLabels($first: Int!) {
           issueLabels(first: $first) { nodes { id name color description team { id key } } }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.issueLabels.nodes;
      return ok({ labels: n, count: n.length });
    }

    case "linear_list_workflow_states": {
      const r = await graphql(
        `query ListWorkflowStates($first: Int!, $filter: WorkflowStateFilter) {
           workflowStates(first: $first, filter: $filter) {
             nodes { id name type color position team { id key } }
           }
         }`,
        { first: limit, filter: a.team_id ? { team: { id: { eq: a.team_id } } } : undefined },
      );
      if (r.error) return r;
      const n = r.data.workflowStates.nodes;
      return ok({ states: n, count: n.length });
    }

    // ── Users ─────────────────────────────────────────────────────────────

    case "linear_list_users": {
      const r = await graphql(
        `query ListUsers($first: Int!) {
           users(first: $first) { nodes { id name displayName email active admin } }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.users.nodes;
      return ok({ users: n, count: n.length });
    }

    case "linear_whoami": {
      const r = await graphql(
        `query Whoami {
           viewer { id name displayName email admin }
           organization { id name urlKey }
         }`,
      );
      if (r.error) return r;
      return ok({ viewer: r.data.viewer, organization: r.data.organization });
    }

    // ── Documents & initiatives ───────────────────────────────────────────

    case "linear_list_documents": {
      const r = await graphql(
        `query ListDocuments($first: Int!) {
           documents(first: $first) {
             nodes { id title icon url createdAt updatedAt creator { id name } }
           }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.documents.nodes;
      return ok({ documents: n, count: n.length });
    }

    case "linear_get_document": {
      if (!a.document_id) return missing("document_id");
      const r = await graphql(
        `query GetDocument($id: String!) {
           document(id: $id) { id title content icon url createdAt updatedAt }
         }`,
        { id: a.document_id },
      );
      if (r.error) return r;
      if (!r.data.document) return { status: 404, error: `Document not found: ${a.document_id}` };
      return ok({ document: r.data.document });
    }

    case "linear_list_initiatives": {
      const r = await graphql(
        `query ListInitiatives($first: Int!) {
           initiatives(first: $first) {
             nodes { id name description status targetDate url owner { id name } }
           }
         }`,
        { first: limit },
      );
      if (r.error) return r;
      const n = r.data.initiatives.nodes;
      return ok({ initiatives: n, count: n.length });
    }

    // ── Attachments ───────────────────────────────────────────────────────

    case "linear_create_attachment": {
      if (!a.issue_id) return missing("issue_id");
      if (!a.url) return missing("url");
      const input = { issueId: a.issue_id, url: a.url };
      if (a.title) input.title = a.title;
      if (a.subtitle) input.subtitle = a.subtitle;
      const r = await graphql(
        `mutation CreateAttachment($input: AttachmentCreateInput!) {
           attachmentCreate(input: $input) { success attachment { id title subtitle url } }
         }`,
        { input },
      );
      if (r.error) return r;
      return ok(r.data.attachmentCreate);
    }

    default:
      return { status: 404, error: `Unknown linear-mcp tool: ${toolName}` };
  }
}

// ---------------------------------------------------------------------------
// Shared issue-mutation path — update / assign / prioritise / move funnel here.
// ---------------------------------------------------------------------------

async function updateIssue(id, input) {
  const r = await graphql(
    `mutation UpdateIssue($id: String!, $input: IssueUpdateInput!) {
       issueUpdate(id: $id, input: $input) { success issue { ${ISSUE_FIELDS} } }
     }`,
    { id, input },
  );
  if (r.error) return r;
  return ok(r.data.issueUpdate);
}

// ---------------------------------------------------------------------------
// Cartridge metadata — read by the BoJ loader to register this cartridge's
// tools without re-reading cartridge.json.
// ---------------------------------------------------------------------------

export const metadata = {
  name: "linear-mcp",
  version: "0.2.0",
  domain: "project-management",
  tier: "Ayo",
  protocols: ["MCP", "GraphQL"],
  toolCount: 27,
};
