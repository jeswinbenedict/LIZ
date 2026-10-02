// ---------------------------------------------------------------------------
// Not every popular repo is a product.
//
// GitHub's topic search returns courses, awesome-lists and prompt dumps
// alongside real tools, and publishing those as "AI tools" is what answered
// "review my pull requests" with a curated link list and a terminal statusline.
// Someone browsing Liz wants something they can use, not something to read.
// ---------------------------------------------------------------------------

const NON_PRODUCT_TOPICS = new Set([
  'awesome', 'awesome-list', 'awesome-lists', 'tutorial', 'tutorials', 'course',
  'courses', 'learning', 'education', 'educational', 'book', 'books', 'ebook',
  'cheatsheet', 'roadmap', 'interview', 'interview-questions', 'papers', 'paper',
  'study', 'curriculum', 'workshop', 'examples', 'demo', 'boilerplate',
  'template', 'starter', 'list', 'collection', 'resources',
]);

// Matched against the repo name, where these words are decisive.
const NON_PRODUCT_NAME = [
  /awesome/i,
  /\b(course|courses|tutorial|tutorials|lesson|lessons)\b/i,
  /(^|[-_])(beginners?|101|basics|bootcamp|workshop|curriculum)([-_]|$)/i,
  /(^|[-_])learn([-_]|$)/i,
  /from[-_ ]scratch/i,
  /\b(roadmap|cheat[-_ ]?sheet|checklist|handbook|guide|guides|glossary)\b/i,
  /\b(leaks?|dumps?)\b/i,
  /\b(examples?|samples?|boilerplate|template|starter[-_ ]?kit)\b/i,
  // "prompt" is deliberately absent: prompt-optimizer is a real tool, while a
  // prompt *collection* is caught by the description rules instead.
  /(^|[-_])(list|lists|gallery|collection)([-_]|$)/i,
  /[-_]list$/i,
];

// Matched against the description. Kept to phrases that only ever describe
// reading material, so a real tool mentioning "examples" is not caught.
const NON_PRODUCT_DESCRIPTION = [
  /\b\d+\s+lessons?\b/i,
  /\b(a\s+)?(curated|comprehensive)\s+(list|collection|repository)\b/i,
  /\bone[-\s]stop\s+(repository|shop|resource)\b/i,
  /\b(list|collection)\s+of\s+(awesome|free|useful|the\s+best)\b/i,
  /\bcourse\s+to\s+(get|learn)\b/i,
  /\b(learn|teaches?|teaching)\s+(you\s+)?how\s+to\b/i,
  /\bstep[-\s]by[-\s]step\b/i,
  /\b(guides?|papers|notebooks|lessons|resources)\s+(and|,)\s+/i,
  /\bextracted\s+system\s+prompts\b/i,
  // "This GitHub repo is a powerhouse collection …" — allow qualifiers between
  // "this" and "repo", and adjectives before the noun.
  /\bthis\s+(\w+\s+)?repo(sitory)?\s+(is\s+a\s+|showcases|contains|provides)/i,
  /\b(powerhouse|hand[-\s]?curated|comprehensive)\s+(collection|list|resources)\b/i,
  /\bprompt\s+(gallery|library|collection)\b/i,
  /\bimplementation\s+of\s+.*\bin\s+(pytorch|tensorflow|jax)\b/i,
];

export function isNonProduct(
  name: string,
  description: string,
  topics: string[],
): boolean {
  if (topics.some((t) => NON_PRODUCT_TOPICS.has(t.toLowerCase()))) return true;
  if (NON_PRODUCT_NAME.some((re) => re.test(name))) return true;
  if (NON_PRODUCT_DESCRIPTION.some((re) => re.test(description))) return true;
  return false;
}

// ---------------------------------------------------------------------------
// A repo's "homepage" field is whatever its owner typed, and not always a
// home page. Among the rows this wrote: an Amazon affiliate link, a Discord
// invite, a LinkedIn profile, a YouTube channel and an arXiv PDF, each shown
// behind a "Visit" button as the tool's website. For those the repository is
// the better answer — it is at least the thing itself.
// ---------------------------------------------------------------------------

const NOT_A_HOMEPAGE_HOSTS = [
  // social and chat
  'discord.gg', 'discord.com', 'dsc.gg', 'linkedin.com', 'twitter.com', 'x.com',
  'youtube.com', 'youtu.be', 't.me', 'facebook.com', 'instagram.com',
  // shorteners and affiliate links hide where they go
  'amzn.to', 'amazon.com', 'bit.ly', 'tinyurl.com', 'aka.ms', 'goo.gl',
  // papers are about a tool, not the tool
  'arxiv.org',
];

function hostMatches(host: string, entry: string): boolean {
  return host === entry || host.endsWith(`.${entry}`);
}

/** The URL to show as a GitHub tool's website: its homepage if it is one. */
export function websiteFor(homepage: string | null | undefined, repoUrl: string): string {
  if (!homepage) return repoUrl;
  let url: URL;
  try {
    url = new URL(homepage.trim());
  } catch {
    return repoUrl;
  }
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return repoUrl;
  const host = url.hostname.toLowerCase().replace(/^www\./, '');
  if (NOT_A_HOMEPAGE_HOSTS.some((entry) => hostMatches(host, entry))) return repoUrl;
  if (/\.(pdf|zip|docx?|pptx?)$/i.test(url.pathname)) return repoUrl;
  // Campaign tags say where a click came from; the catalog is not GitHub.
  for (const key of [...url.searchParams.keys()]) {
    if (key.toLowerCase().startsWith('utm_')) url.searchParams.delete(key);
  }
  return url.toString();
}

/// A repository description cut down to a tagline. Slicing at a fixed length
/// left taglines ending mid-word ("one CLI, zero AP") or on a dangling "&";
/// cut at a word instead, drop whatever joins the cut-off half, and say that
/// there is more.
export function clipTagline(text: string, limit = 140): string {
  const clean = text.replace(/\s+/g, ' ').trim();
  if (clean.length <= limit) return clean;
  const cut = clean.slice(0, limit - 1);
  const atWord = cut.includes(' ') ? cut.slice(0, cut.lastIndexOf(' ')) : cut;
  const tidy = atWord.replace(/(\s+(&|and|or|with|the|a|an|of|to|for))+$/i, '')
    .replace(/[\s,;:&—–-]+$/, '');
  return `${tidy}…`;
}
