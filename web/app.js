/* Garage panel. Lua sends each vehicle's status and buttons; only an ID and a chosen action leave this page. */
(() => {
  'use strict';
  const $ = (id) => document.getElementById(id);
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'h4nr-garages';
  const post = (name, body) => fetch(`https://${resource}/${name}`, { method: 'POST', body: JSON.stringify(body || {}) })
    .then((response) => response.json());
  let session = null, texts = {}, items = [], selected = null, filter = 'all', query = '', busy = false;
  // Slot meters and premium offers; `armed` is the offer waiting for its confirming click.
  let slots = null, armed = null;

  function node(tag, className, text) {
    const element = document.createElement(tag);
    if (className) element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  }
  function counts() {
    return { all: items.length, stored: items.filter((item) => item.group === 'stored').length, out: items.filter((item) => item.group === 'out').length };
  }
  function visible() {
    const needle = query.trim().toLowerCase();
    return items.filter((item) => (filter === 'all' || item.group === filter)
      && (!needle || item.name.toLowerCase().includes(needle) || item.plate.toLowerCase().includes(needle)));
  }
  // Nearby vehicles come first, in the order they are drawn.
  function ordered() {
    const shown = visible();
    return [...shown.filter((item) => item.nearby), ...shown.filter((item) => !item.nearby)];
  }
  function current() {
    return items.find((item) => item.id === selected) || null;
  }
  // Keeps the selection when it is still shown; otherwise the first vehicle something can be done with.
  function settleSelection() {
    const shown = ordered();
    if (shown.some((item) => item.id === selected)) return;
    const usable = shown.find((item) => item.actions.some((action) => !action.disabled));
    selected = (usable || shown[0] || {}).id ?? null;
  }
  function bar(label, value) {
    const element = node('span', `bar${value <= 25 ? ' danger' : value <= 50 ? ' warn' : ''}`);
    const head = node('span', 'bar-head');
    head.append(node('b', '', label), node('em', '', `${value}%`));
    const track = node('span', 'track');
    const fill = node('i');
    fill.style.width = `${value}%`;
    track.append(fill);
    element.append(head, track);
    return element;
  }
  function row(item) {
    const button = node('button', `row${item.id === selected ? ' selected' : ''}`);
    button.type = 'button';
    button.dataset.id = item.id;
    button.setAttribute('aria-pressed', String(item.id === selected));
    const top = node('span', 'row-top');
    top.append(node('span', 'name', item.name), node('span', 'plate', item.plate));
    button.append(top, node('span', `status ${item.tone}`, item.status));
    const condition = item.condition || {};
    const parts = [['engine', condition.engine], ['body', condition.body], ['fuel', condition.fuel]].filter((part) => typeof part[1] === 'number');
    if (parts.length) {
      const bars = node('span', 'bars');
      for (const [key, value] of parts) bars.append(bar(texts[key], value));
      button.append(bars);
    }
    button.addEventListener('click', () => select(item.id));
    return button;
  }
  function renderFilters() {
    const total = counts();
    const host = $('filters');
    host.replaceChildren();
    for (const [key, label] of [['all', 'filter_all'], ['stored', 'filter_stored'], ['out', 'filter_out']]) {
      const button = node('button', `filter${filter === key ? ' active' : ''}`, `${texts[label]} ${total[key]}`);
      button.type = 'button';
      button.setAttribute('aria-pressed', String(filter === key));
      button.addEventListener('click', () => { filter = key; settleSelection(); render(); });
      host.append(button);
    }
  }
  function renderList(keepFocus) {
    const host = $('list');
    const shown = ordered();
    const nearby = shown.filter((item) => item.nearby);
    const rest = shown.filter((item) => !item.nearby);
    host.replaceChildren();
    if (!shown.length) host.append(node('div', 'empty', items.length ? texts.no_match : texts.no_vehicles));
    if (nearby.length) {
      host.append(node('span', 'section', texts.section_nearby));
      for (const item of nearby) host.append(row(item));
      if (rest.length) host.append(node('span', 'section', texts.section_vehicles));
    }
    for (const item of rest) host.append(row(item));
    const chosen = selected !== null ? [...host.querySelectorAll('.row')].find((element) => element.dataset.id === selected) : null;
    if (chosen) {
      chosen.scrollIntoView({ block: 'nearest' });
      if (keepFocus) chosen.focus();
    }
  }
  function renderFoot() {
    const item = current();
    const shown = item && ordered().includes(item) ? item : null;
    $('reason').hidden = !(shown && shown.reason);
    $('reason').textContent = shown && shown.reason || '';
    const host = $('actions');
    host.replaceChildren();
    if (!shown) return;
    shown.actions.forEach((action, index) => {
      const button = node('button', index === 0 ? 'primary' : 'secondary', action.label);
      button.type = 'button';
      button.disabled = busy || Boolean(action.disabled);
      button.addEventListener('click', () => run(shown, action));
      host.append(button);
    });
  }
  function meter(entry) {
    const full = entry.used >= entry.limit;
    const element = node('div', `meter${full ? ' full' : ''}`);
    const head = node('span', 'bar-head');
    head.append(node('b', '', entry.label), node('em', '', `${entry.used}/${entry.limit}`));
    const track = node('span', 'track');
    const fill = node('i');
    fill.style.width = `${entry.limit > 0 ? Math.min(100, Math.round(entry.used / entry.limit * 100)) : 100}%`;
    track.append(fill);
    element.append(head, track);
    return element;
  }
  function renderSlots() {
    const host = $('slots');
    host.hidden = !slots;
    if (!slots) return;
    $('meters').replaceChildren(...(slots.meters || []).map(meter));
    const offers = $('offers');
    offers.replaceChildren();
    for (const offer of slots.offers || []) {
      const button = node('button', `offer${armed === offer.id ? ' armed' : ''}`);
      button.type = 'button';
      button.disabled = busy;
      button.append(node('span', 'offer-tag', texts.slots_premium), node('span', '', armed === offer.id ? texts.slot_confirm : offer.label));
      button.addEventListener('click', () => buySlot(offer));
      offers.append(button);
    }
  }
  async function buySlot(offer) {
    if (busy) return;
    if (armed !== offer.id) { armed = offer.id; showNotice(''); renderSlots(); return; }
    armed = null;
    const active = session;
    setBusy(true);
    showNotice('');
    let result = null;
    try {
      result = await post('slot', { session: active, id: offer.id });
    } catch {
      result = null;
    }
    if (session !== active) { busy = false; return; }
    setBusy(false);
    showNotice(result && result.message || '', Boolean(result && result.ok));
  }
  function render(keepFocus) {
    renderSlots();
    renderFilters();
    renderList(keepFocus);
    renderFoot();
  }
  function select(id) {
    selected = id;
    armed = null;
    showNotice('');
    render(true);
  }
  function showNotice(text, success) {
    const notice = $('notice');
    notice.hidden = !text;
    notice.textContent = text || '';
    notice.classList.toggle('success', Boolean(success));
  }
  function setBusy(value) {
    busy = value;
    renderSlots();
    renderFoot();
  }
  async function run(item, action) {
    if (busy || action.disabled) return;
    const active = session;
    setBusy(true);
    showNotice('');
    let result = null;
    try {
      result = await post('action', { session: active, assetId: item.id, id: action.id, method: action.method });
    } catch {
      result = null;
    }
    if (session !== active) { busy = false; return; }
    setBusy(false);
    if (result && result.closed) return;
    showNotice(result && result.message || '', Boolean(result && result.ok));
  }
  function close() {
    post('close').catch(() => {});
  }
  function move(step) {
    const shown = ordered();
    if (!shown.length) return;
    const index = shown.findIndex((item) => item.id === selected);
    select(shown[Math.min(shown.length - 1, Math.max(0, index + step))].id);
  }
  function activate() {
    const item = current();
    const action = item && item.actions.find((candidate) => !candidate.disabled);
    if (item && action && ordered().includes(item)) run(item, action);
  }

  $('close').addEventListener('click', close);
  $('search').addEventListener('input', (event) => { query = event.target.value; settleSelection(); render(); });
  document.addEventListener('keydown', (event) => {
    if (session === null) return;
    if (event.key === 'Escape') { event.preventDefault(); close(); }
    else if (event.key === 'ArrowDown') { event.preventDefault(); move(1); }
    else if (event.key === 'ArrowUp') { event.preventDefault(); move(-1); }
    else if (event.key === 'Enter' && event.target === $('search')) { event.preventDefault(); activate(); }
  });
  window.addEventListener('message', ({ data }) => {
    if (!data || typeof data !== 'object') return;
    if (data.action === 'open') {
      session = data.session;
      texts = data.texts || {};
      items = [];
      selected = null; filter = 'all'; query = ''; busy = false; slots = null; armed = null;
      $('kind').textContent = data.kind || '';
      $('garage-name').textContent = data.label || '';
      $('search').value = '';
      $('search').placeholder = texts.search || '';
      $('close').setAttribute('aria-label', texts.close || '');
      showNotice('');
      $('app').hidden = false;
      $('search').focus();
    } else if (data.action === 'view' && data.session === session) {
      items = Array.isArray(data.items) ? data.items : [];
      slots = data.slots && typeof data.slots === 'object' ? data.slots : null;
      settleSelection();
      render();
    } else if (data.action === 'close') {
      session = null;
      items = [];
      slots = null; armed = null;
      $('app').hidden = true;
      if (document.activeElement) document.activeElement.blur();
    }
  });
  post('ready').catch(() => {});
})();
