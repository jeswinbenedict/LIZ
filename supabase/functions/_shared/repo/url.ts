// Turning what a person pastes into a repository to analyse.
//
// People paste every shape GitHub shows them: the page address, a link to a
// branch or a file in it, the clone address (HTTPS or SSH), or just
// "owner/name". All of them name the same thing, so all are accepted; anything
// else is refused here, before a single request is spent on it.

export interface RepoRef {
  owner: string;
  repo: string;
  /** A branch, tag or commit named in the address (`/tree/<ref>`), if any. */
  ref?: string;
}

// GitHub's own rules: owners are 1-39 of letters, digits and single hyphens;
// repository names are letters, digits, '.', '-' and '_', at most 100.
const OWNER = /^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$/;
const NAME = /^[A-Za-z0-9._-]{1,100}$/;

/// The repository an address names, or null when it names none.
export function parseRepoUrl(input: string): RepoRef | null {
  let s = (input ?? '').trim();
  if (!s || s.length > 500) return null;

  // The clone commands GitHub's "Code" button offers, pasted whole:
  //   gh repo clone owner/name [directory] [-- git flags]
  //   git clone [flags] <url> [directory]
  const gh = /^gh\s+repo\s+clone\s+(\S+)/i.exec(s);
  if (gh) s = gh[1];
  const words = s.split(/\s+/);
  if (words[0]?.toLowerCase() === 'git' && words[1]?.toLowerCase() === 'clone') {
    s = words.slice(2).find((w) => /github\.com/i.test(w)) ?? '';
  }
  // `gh` also accepts a full URL, and ssh:// is the long form of git@.
  s = s.replace(/^ssh:\/\/git@github\.com[:/]/i, 'git@github.com:');

  // git@github.com:owner/name.git
  const ssh = /^git@github\.com:([^/]+)\/([^/]+?)(?:\.git)?\/?$/i.exec(s);
  if (ssh) return checked(ssh[1], ssh[2]);

  // owner/name, nothing else
  // owner/name. An owner can never contain a dot, so "github.com/x" is not
  // mistaken for an owner called "github.com".
  const bare = /^([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)$/.exec(s);
  if (bare) return checked(bare[1], bare[2].replace(/\.git$/i, ''));

  if (!/^https?:\/\//i.test(s)) s = `https://${s}`;
  let url: URL;
  try {
    url = new URL(s);
  } catch (_) {
    return null;
  }
  const host = url.hostname.toLowerCase();
  if (host !== 'github.com' && host !== 'www.github.com') return null;
  const parts = url.pathname.split('/').filter(Boolean).map(decodeURIComponent);
  if (parts.length < 2) return null;
  const found = checked(parts[0], parts[1].replace(/\.git$/i, ''));
  if (!found) return null;
  // /owner/name/tree/<ref>[/path] or /blob/<ref>/path or /commit/<sha>
  if ((parts[2] === 'tree' || parts[2] === 'blob' || parts[2] === 'commit') && parts[3]) {
    found.ref = parts[3];
  }
  return found;
}

function checked(owner: string, repo: string): RepoRef | null {
  if (!OWNER.test(owner) || !NAME.test(repo) || repo === '.' || repo === '..') return null;
  return { owner, repo };
}

/// A branch, tag or commit name safe to put in a URL path, or null.
export function cleanRef(ref: unknown): string | null {
  if (typeof ref !== 'string') return null;
  const r = ref.trim();
  if (!r || r.length > 200) return null;
  // Git's ref rules, roughly: no spaces, no '..', no control characters, no
  // leading '-' (which a CLI would read as an option; we never run one, but a
  // ref like that is not a real branch either).
  if (/[\s~^:?*[\\\x00-\x1f]|\.\.|^-|\/$|@\{/.test(r)) return null;
  return r;
}
