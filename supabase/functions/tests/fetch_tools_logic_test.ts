import { assert, assertEquals } from 'jsr:@std/assert@1';
import { isNonProduct, websiteFor } from '../fetch-tools/logic.ts';

// GitHub's topic search returns plenty that isn't a product. These are real
// repos that reached the live catalog and had to be hidden by hand, plus the
// real tools that must survive the same rules.

Deno.test('rejects courses and lesson repos', () => {
  assert(isNonProduct('generative-ai-for-beginners', '21 Lessons, Get Started Building with Generative AI', []));
  assert(isNonProduct('llm-course', 'Course to get into Large Language Models', []));
  assert(isNonProduct('LLMs-from-scratch', 'Implement a ChatGPT-like LLM in PyTorch from scratch', []));
  assert(isNonProduct('learn-claude-code', 'A nano claude code-like agent harness', []));
});

Deno.test('rejects awesome-lists and curated collections', () => {
  assert(isNonProduct('awesome-generative-ai', 'A curated list of Generative AI tools', []));
  assert(isNonProduct('API-mega-list', 'This GitHub repo is a powerhouse collection of APIs', []));
  assert(isNonProduct('Front-End-Checklist', 'The essential checklist for modern web development', []));
});

Deno.test('rejects prompt dumps and galleries', () => {
  assert(isNonProduct('system_prompts_leaks', 'Extracted system prompts from Anthropic', []));
  assert(isNonProduct('GPT-Image2-Skill', 'GPT Image 2 prompt gallery, image prompt library', []));
});

Deno.test('rejects on the repo topics even when name and text look fine', () => {
  // Stable-Diffusion self-tags as education; ai-website-cloner-template as boilerplate.
  assert(isNonProduct('Stable-Diffusion', 'FLUX, SDXL, LoRA, Fine Tuning', ['education']));
  assert(isNonProduct('some-tool', 'Clone any website with one command', ['boilerplate']));
});

Deno.test('keeps real products', () => {
  const products: [string, string][] = [
    ['ollama', 'Get up and running with large language models locally'],
    ['open-webui', 'User-friendly AI Interface'],
    ['OpenVoice', 'Instant voice cloning by MIT and MyShell'],
    ['firecrawl', 'The context API to search, scrape, and interact with the web'],
    ['repomix', 'Packs your entire repository into a single file'],
    ['CopilotKit', 'The Frontend Stack for Agents & Generative UI'],
  ];
  for (const [name, description] of products) {
    assertEquals(isNonProduct(name, description, []), false, `${name} should be kept`);
  }
});

Deno.test('"prompt" in a name does not disqualify a real tool', () => {
  // prompt-optimizer is a product; only prompt *collections* should go.
  assertEquals(
    isNonProduct('prompt-optimizer', 'An AI prompt optimizer for writing better prompts', []),
    false,
  );
});

Deno.test('handles empty input without throwing', () => {
  assertEquals(isNonProduct('', '', []), false);
});

const REPO = 'https://github.com/acme/tool';

Deno.test('a real homepage is the website', () => {
  assertEquals(websiteFor('https://ollama.com', REPO), 'https://ollama.com/');
  assertEquals(websiteFor('https://docs.langchain.com/oss/', REPO), 'https://docs.langchain.com/oss/');
});

Deno.test('a homepage that is not one falls back to the repository', () => {
  // Each of these reached the catalog as a tool's website.
  for (const bad of [
    'https://amzn.to/4fqvn0D',
    'https://discord.gg/m88xfYMbK6',
    'https://www.linkedin.com/in/areganti/',
    'https://www.youtube.com/SECourses',
    'https://dsc.gg/jcodesmore',
    'https://arxiv.org/pdf/2412.20138',
    'https://example.com/whitepaper.pdf',
    'ftp://example.com',
    'not a url',
    '',
    null,
  ]) {
    assertEquals(websiteFor(bad, REPO), REPO, String(bad));
  }
});

Deno.test('campaign tags are stripped, other parameters kept', () => {
  assertEquals(
    websiteFor('https://muapi.ai/open?utm_source=github&utm_medium=about&ref=x', REPO),
    'https://muapi.ai/open?ref=x',
  );
});
