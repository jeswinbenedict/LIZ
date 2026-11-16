// Reading a repository from GitHub, and nothing else.
//
// Everything goes through the REST API (repository, branches, commit, the Git
// Trees API for the whole file list in one call) except file contents of a
// public repository, which come from raw.githubusercontent.com: those do not
// count against the API's allowance (60 an hour without a token), which a
// hundred files would otherwise exhaust in one analysis.
//
// A token, when given, is the person's own and is used only for the calls of
// the analysis it came with. It is never stored, never logged, and never put
// in an error message (errors carry GitHub's status and message, not ours).

export type Fetch = typeof fetch;

export class GitHubError extends Error {
  constructor(
    message: string,
    /** 'not_found' | 'forbidden' | 'bad_token' | 'rate_limited' | 'too_large' | 'upstream' */
    readonly code: string,
    /** For 'rate_limited': when the allowance comes back, epoch seconds. */
    readonly resetAt?: number,
  ) {
    super(message);
  }
}

export interface RepoInfo {
  fullName: string;
  description: string | null;
  defaultBranch: string;
  private: boolean;
  stars: number;
  forks: number;
  openIssues: number;
  license: string | null;
  homepage: string | null;
  topics: string[];
  sizeKb: number;
  pushedAt: string | null;
  createdAt: string | null;
  archived: boolean;
}

export interface TreeEntry {
  path: string;
  type: 'blob' | 'tree' | 'commit';
  sha: string;
  size?: number;
}

export class GitHub {
  /** API calls made, for the run's statistics. */
  calls = 0;

  constructor(
    private readonly token: string | null,
    private readonly fetchFn: Fetch = fetch,
    private readonly api = 'https://api.github.com',
  ) {}

  get authenticated(): boolean {
    return !!this.token;
  }

  private async get(path: string, accept = 'application/vnd.github+json'): Promise<Response> {
    const headers: Record<string, string> = {
      Accept: accept,
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'Liz-Repository-Analyzer',
    };
    if (this.token) headers.Authorization = `Bearer ${this.token}`;
    this.calls++;
    let res = await this.fetchFn(`${this.api}${path}`, { headers });
    // Secondary limits answer with Retry-After; one short wait is worth it,
    // a long one is not (the analysis has a wall clock).
    const retry = Number(res.headers.get('retry-after'));
    if ((res.status === 403 || res.status === 429) && retry > 0 && retry <= 10) {
      await new Promise((r) => setTimeout(r, retry * 1000));
      this.calls++;
      res = await this.fetchFn(`${this.api}${path}`, { headers });
    }
    if (!res.ok) throw await errorFrom(res, !!this.token);
    return res;
  }

  async repo(owner: string, repo: string): Promise<RepoInfo> {
    const j = await (await this.get(`/repos/${owner}/${repo}`)).json();
    return {
      fullName: j.full_name,
      description: j.description ?? null,
      defaultBranch: j.default_branch,
      private: !!j.private,
      stars: j.stargazers_count ?? 0,
      forks: j.forks_count ?? 0,
      openIssues: j.open_issues_count ?? 0,
      license: j.license?.spdx_id && j.license.spdx_id !== 'NOASSERTION' ? j.license.spdx_id : null,
      homepage: j.homepage || null,
      topics: Array.isArray(j.topics) ? j.topics : [],
      sizeKb: j.size ?? 0,
      pushedAt: j.pushed_at ?? null,
      createdAt: j.created_at ?? null,
      archived: !!j.archived,
    };
  }

  /** Up to a hundred branches, the default first. */
  async branches(owner: string, repo: string): Promise<string[]> {
    const j = await (await this.get(`/repos/${owner}/${repo}/branches?per_page=100`)).json();
    return Array.isArray(j) ? j.map((b: { name: string }) => b.name) : [];
  }

  /** The commit a branch, tag or SHA points at, and its date. */
  async commit(owner: string, repo: string, ref: string): Promise<{ sha: string; date: string | null; message: string }> {
    const j = await (await this.get(`/repos/${owner}/${repo}/commits/${encodeURIComponent(ref)}`)).json();
    return {
      sha: j.sha,
      date: j.commit?.committer?.date ?? null,
      message: String(j.commit?.message ?? '').split('\n')[0].slice(0, 200),
    };
  }

  /** Every file and folder at a commit, in one call. */
  async tree(owner: string, repo: string, sha: string): Promise<{ entries: TreeEntry[]; truncated: boolean }> {
    const j = await (await this.get(`/repos/${owner}/${repo}/git/trees/${sha}?recursive=1`)).json();
    return { entries: Array.isArray(j.tree) ? j.tree : [], truncated: !!j.truncated };
  }

  /** Bytes of code per language, as GitHub's own linguist counts them. */
  async languages(owner: string, repo: string): Promise<Record<string, number>> {
    try {
      return await (await this.get(`/repos/${owner}/${repo}/languages`)).json();
    } catch (_) {
      return {};
    }
  }

  /**
   * One file's text at a commit. Public files come from raw.githubusercontent
   * (no allowance spent); with a token, from the API, which also serves
   * private repositories.
   */
  async text(owner: string, repo: string, sha: string, path: string): Promise<string> {
    const encoded = path.split('/').map(encodeURIComponent).join('/');
    if (!this.token) {
      const res = await this.fetchFn(`https://raw.githubusercontent.com/${owner}/${repo}/${sha}/${encoded}`, {
        headers: { 'User-Agent': 'Liz-Repository-Analyzer' },
      });
      if (!res.ok) throw new GitHubError(`Could not read ${path} (${res.status})`, res.status === 404 ? 'not_found' : 'upstream');
      return await res.text();
    }
    const res = await this.get(`/repos/${owner}/${repo}/contents/${encoded}?ref=${sha}`, 'application/vnd.github.raw');
    return await res.text();
  }
}

async function errorFrom(res: Response, withToken: boolean): Promise<GitHubError> {
  let message = '';
  try {
    message = String((await res.json())?.message ?? '');
  } catch (_) {
    // Not JSON: keep the status alone.
  }
  const remaining = res.headers.get('x-ratelimit-remaining');
  const reset = Number(res.headers.get('x-ratelimit-reset')) || undefined;
  if ((res.status === 403 || res.status === 429) && (remaining === '0' || /rate limit/i.test(message))) {
    return new GitHubError(
      withToken
        ? 'GitHub’s request limit for this token is used up.'
        : 'GitHub’s request limit for anonymous use is used up. Add a token, or try again after it resets.',
      'rate_limited',
      reset,
    );
  }
  if (res.status === 401) return new GitHubError('GitHub did not accept that token.', 'bad_token');
  if (res.status === 404) {
    return new GitHubError(
      withToken
        ? 'No repository, branch or commit by that name is visible to this token.'
        : 'No public repository, branch or commit by that name. If it is private, add a token that can read it.',
      'not_found',
    );
  }
  if (res.status === 403) return new GitHubError('GitHub refused access to this repository.', 'forbidden');
  if (res.status === 409) return new GitHubError('This repository is empty.', 'not_found');
  return new GitHubError(`GitHub answered ${res.status}${message ? `: ${message.slice(0, 120)}` : ''}.`, 'upstream');
}
