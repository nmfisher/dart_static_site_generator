import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';
import AtCommentsWidget from '../src/at_comments.js';

// A DOM double that rejects every HTML parsing sink. Externally supplied values
// must reach textContent/dataset intact, even when they contain markup or quotes.
class Element {
  constructor(tag) {
    this.tagName = tag;
    this.children = [];
    this.dataset = {};
    this.listeners = {};
    this.classList = { add() {} };
  }
  set innerHTML(_) { throw new Error('Comment rendering must not parse HTML'); }
  appendChild(child) { this.children.push(child); }
  addEventListener(type, callback) { this.listeners[type] = callback; }
}
const document = {
  createElement: tag => new Element(tag),
  getElementById: () => new Element('div'),
};
const fetchThread = async () => ({
  ok: true,
  json: async () => ({ thread: { post: { replyCount: 0 }, replies: [] } }),
});
const widgets = [['source', AtCommentsWidget]];
for (const [name, file] of [['shipped bundle', '../../lib/src/defaults/assets/js/at_comments.js'], ['local bundle', '../at_comments.js']]) {
  const context = vm.createContext({ document, window: {}, fetch: fetchThread });
  vm.runInContext(readFileSync(new URL(file, import.meta.url), 'utf8'), context);
  widgets.push([name, context.window.AtCommentsWidget]);
}

for (const [name, Widget] of widgets) {
  test(`${name}: loading retains the existing CAPTCHA gate`, async () => {
    const oldDocument = globalThis.document;
    const oldFetch = globalThis.fetch;
    globalThis.document = document;
    globalThis.fetch = fetchThread;
    try {
      const widget = new Widget('comments', 'at://did:plc:test/app.bsky.feed.post/root');
      widget.container = { innerHTML: '' };
      let gates = 0;
      let forms = 0;
      widget.renderCaptchaGate = () => { gates++; };
      widget.renderCommentForm = () => { forms++; };
      await widget.loadComments();
      assert.equal(gates, 1);
      assert.equal(forms, 0);
    } finally {
      globalThis.document = oldDocument;
      globalThis.fetch = oldFetch;
    }
  });
  test(`${name}: comment quotes and markup remain data`, () => {
    const oldDocument = globalThis.document;
    globalThis.document = document;
    try {
      const widget = new Widget('comments', 'at://did:plc:test/app.bsky.feed.post/root');
      const text = '" onmouseover="alert(1) <img src=x onerror=alert(1)> & text';
      const uri = 'at://did:plc:test/app.bsky.feed.post/reply" onclick="alert(1)';
      let reply;
      widget.setReplyTo = (...args) => { reply = args; };
      const element = widget.createCommentElement({ uri, record: { text, createdAt: '2024-01-15T12:00:00Z' } });
      const body = element.children.find(child => child.className === 'at-comment-body');
      const button = element.children.find(child => child.tagName === 'button');
      assert.equal(body.textContent, text);
      assert.equal(button.dataset.text, text);
      assert.equal(button.dataset.uri, uri);
      assert.deepEqual(Object.keys(button.listeners), ['click']);
      button.listeners.click();
      assert.deepEqual(reply, [uri, text]);
      assert.ok(element.children.some(child => child.className === 'at-comment-date'));
    } finally {
      globalThis.document = oldDocument;
    }
  });
}
