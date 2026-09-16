(() => {
  const form = document.getElementById('site-search');
  if (!form) return;
  const input = document.getElementById('search-query');
  const results = document.getElementById('search-results');
  const status = document.getElementById('search-status');
  let index;
  let generation = 0;
  async function search(event) {
    event?.preventDefault();
    const current = ++generation;
    const query = input.value.trim();
    const terms = query.toLocaleLowerCase().split(/\s+/).filter(Boolean);
    results.replaceChildren();
    if (!terms.length) { status.textContent = 'Enter a search term.'; return; }
    status.textContent = 'Searching…';
    try {
      index ||= fetch(form.dataset.index).then(response => {
        if (!response.ok) throw new Error('Search index unavailable');
        return response.json();
      }).catch(error => { index = null; throw error; });
      const records = await index;
      if (current !== generation) return;
      const matches = records.map(record => {
        const title = record.title.toLocaleLowerCase();
        const text = `${record.title} ${record.text} ${record.tags}`.toLocaleLowerCase();
        return { record, score: terms.every(term => text.includes(term)) ? terms.reduce((n, term) => n + (title.includes(term) ? 10 : 1), 0) : 0 };
      }).filter(item => item.score).sort((a, b) => b.score - a.score).slice(0, 50);
      for (const {record} of matches) {
        const item = document.createElement('li');
        const link = document.createElement('a');
        link.href = record.url; link.textContent = record.title;
        const excerpt = document.createElement('p');
        excerpt.textContent = record.text.slice(0, 220);
        item.append(link, excerpt); results.append(item);
      }
      status.textContent = matches.length ? `${matches.length} result${matches.length === 1 ? '' : 's'}.` : 'No results found.';
    } catch (_) { if (current === generation) status.textContent = 'Search is unavailable. Please try again.'; }
  }
  form.addEventListener('submit', search);
  let timer;
  input.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(search, 150); });
  input.value = new URLSearchParams(location.search).get('q') || '';
  if (input.value) search();
})();
