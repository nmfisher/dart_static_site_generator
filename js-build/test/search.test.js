import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../../lib/src/defaults/assets/js/search.js', import.meta.url), 'utf8');
class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.listeners = {}; this.dataset = {}; this.value = ''; }
  set innerHTML(_) { throw new Error('Search must render text safely'); }
  append(...children) { this.children.push(...children); }
  replaceChildren() { this.children = []; }
  addEventListener(event, fn) { this.listeners[event] = fn; }
}
function setup(fetch) {
  const nodes = Object.fromEntries(['site-search', 'search-query', 'search-results', 'search-status'].map(id => [id, new Element(id)]));
  nodes['site-search'].dataset.index = '/docs/search-index.json';
  const context = vm.createContext({ document: { getElementById: id => nodes[id], createElement: tag => new Element(tag) }, fetch, location: {search: ''}, URLSearchParams, setTimeout, clearTimeout });
  vm.runInContext(source, context);
  return { nodes, submit: query => { nodes['search-query'].value = query; return nodes['site-search'].listeners.submit({preventDefault() {}}); } };
}
test('search ranks titles, matches all words, reuses index and renders markup as text', async () => {
  let requests = 0;
  const {nodes, submit} = setup(async url => {
    requests++; assert.equal(url, '/docs/search-index.json');
    return {ok: true, json: async () => [
      { title: 'Other', text: 'Dart tutorial', tags: [], url: '/docs/other/' },
      { title: 'Dart <img onerror=evil()>', text: 'Tutorial & examples', tags: ['code'], url: '/docs/dart/' },
      { title: 'Dart alone', text: '', tags: [], url: '/docs/alone/' },
    ]};
  });
  await submit('dart tutorial');
  const results = nodes['search-results'].children;
  assert.equal(results.length, 2);
  assert.equal(results[0].children[0].textContent, 'Dart <img onerror=evil()>');
  assert.equal(results[0].children[0].href, '/docs/dart/');
  await submit('no match');
  assert.equal(nodes['search-status'].textContent, 'No results found.');
  await submit('');
  assert.equal(nodes['search-results'].children.length, 0);
  assert.equal(requests, 1);
});
test('search retries a failed fetch', async () => {
  let requests = 0;
  const {nodes, submit} = setup(async () => ({ok: ++requests > 1, json: async () => []}));
  await submit('test');
  assert.match(nodes['search-status'].textContent, /unavailable/);
  await submit('test');
  assert.equal(nodes['search-status'].textContent, 'No results found.');
  assert.equal(requests, 2);
});
test('an older pending query cannot replace newer results', async () => {
  let resolve;
  const response = new Promise(done => { resolve = done; });
  const {nodes, submit} = setup(() => response);
  const first = submit('old');
  const second = submit('new');
  resolve({ok: true, json: async () => [{title:'New', text:'new', tags:[], url:'/new/'}]});
  await Promise.all([first, second]);
  assert.equal(nodes['search-results'].children.length, 1);
  assert.equal(nodes['search-results'].children[0].children[0].textContent, 'New');
});
