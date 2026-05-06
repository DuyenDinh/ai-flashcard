// ═══════════════════════════════════════════════════════
//  AI Flashcard — core app logic
// ═══════════════════════════════════════════════════════

// ── Storage helpers ──────────────────────────────────
const DB_KEY = 'aiflashcard_cards';
const CFG_KEY = 'aiflashcard_config';

function loadCards() {
  try { return JSON.parse(localStorage.getItem(DB_KEY) || '[]'); } catch { return []; }
}
function saveCards(cards) {
  localStorage.setItem(DB_KEY, JSON.stringify(cards));
}
function loadConfig() {
  const defaults = { apiKey: '', targetCEFR: 'B1', dailyGoal: 20, streak: 0, lastReviewDay: null, studyDirection: 'sv-en' };
  try { return { ...defaults, ...JSON.parse(localStorage.getItem(CFG_KEY) || '{}') }; }
  catch { return defaults; }
}
function saveConfig(cfg) { localStorage.setItem(CFG_KEY, JSON.stringify(cfg)); }

// ── SM-2 Algorithm ───────────────────────────────────
// ratings: 0=Again, 1=Hard, 3=Good, 5=Easy
function sm2Review(card, rating) {
  const ef = Math.max(1.3, card.easeFactor + 0.1 - (5 - rating) * (0.08 + (5 - rating) * 0.02));
  card.easeFactor = ef;
  if (rating < 3) {
    card.repetitions = 0;
    card.interval = 1;
  } else {
    if (card.repetitions === 0)      card.interval = 1;
    else if (card.repetitions === 1) card.interval = 6;
    else card.interval = Math.round(card.interval * card.easeFactor);
    card.repetitions++;
  }
  const next = new Date();
  next.setDate(next.getDate() + card.interval);
  card.nextReviewDate = next.toISOString();
  return card;
}

function isDue(card) {
  return new Date(card.nextReviewDate) <= new Date();
}

function dueCards(cards) {
  return cards.filter(isDue).sort((a, b) => new Date(a.nextReviewDate) - new Date(b.nextReviewDate));
}

function makeCard(swedish, english, cefr, exSV='', exEN='', ctx='') {
  return {
    id: crypto.randomUUID(),
    swedish, english, cefr,
    exampleSentenceSV: exSV,
    exampleSentenceEN: exEN,
    sourceContext: ctx,
    createdAt: new Date().toISOString(),
    interval: 1, repetitions: 0, easeFactor: 2.5,
    nextReviewDate: new Date().toISOString()
  };
}

// ── Claude API ────────────────────────────────────────
async function claudeCall(prompt, apiKey) {
  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true'
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-20250514',
      max_tokens: 1024,
      messages: [{ role: 'user', content: prompt }]
    })
  });
  if (res.status === 429) throw new Error('Rate limited — please wait a moment.');
  if (!res.ok) throw new Error(`API error ${res.status}`);
  const data = await res.json();
  return data.content[0].text.trim();
}

function parseJSON(raw) {
  let s = raw.trim();
  // strip markdown fences
  if (s.startsWith('```')) {
    s = s.split('\n').slice(1).join('\n');
    if (s.endsWith('```')) s = s.slice(0, -3);
  }
  return JSON.parse(s.trim());
}

async function translateWord(word, apiKey) {
  const prompt = `Translate the Swedish word '${word}' to English. Classify its CEFR level.
Return ONLY valid JSON (no markdown):
{"swedish":"...","english":"...","cefr":"A1|A2|B1|B2|C1|C2","example_sentence_sv":"...","example_sentence_en":"..."}`;
  const raw = await claudeCall(prompt, apiKey);
  return parseJSON(raw);
}

async function extractVocabulary(text, maxCEFR, apiKey) {
  const prompt = `You are a Swedish language teacher. Extract all unique Swedish words from this text at CEFR level ${maxCEFR} or below. Ignore proper nouns, numbers, punctuation.
Return ONLY a valid JSON array (no markdown):
[{"swedish":"...","english":"...","cefr":"A1|A2|B1|B2|C1|C2"}]

Text:
${text}`;
  const raw = await claudeCall(prompt, apiKey);
  return parseJSON(raw);
}

// ── CEFR colours ──────────────────────────────────────
const CEFR_COLOR = { A1:'#22c55e', A2:'#14b8a6', B1:'#3b82f6', B2:'#6366f1', C1:'#f97316', C2:'#ef4444' };
const CEFR_LEVELS = ['A1','A2','B1','B2','C1','C2'];

// ═══════════════════════════════════════════════════════
//  App State
// ═══════════════════════════════════════════════════════
let cards = loadCards();
let cfg   = loadConfig();

// review session state
let session = { queue: [], index: 0, flipped: false, reviewed: 0 };

// ── Streak ────────────────────────────────────────────
function updateStreak() {
  const today = new Date().toDateString();
  if (cfg.lastReviewDay === today) return;
  const yesterday = new Date(Date.now() - 86400000).toDateString();
  if (cfg.lastReviewDay === yesterday) cfg.streak = (cfg.streak || 0) + 1;
  else cfg.streak = 1;
  cfg.lastReviewDay = today;
  saveConfig(cfg);
}

// ═══════════════════════════════════════════════════════
//  Routing / Navigation
// ═══════════════════════════════════════════════════════
function showScreen(id) {
  document.querySelectorAll('.screen').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  const tab = document.querySelector(`.tab-btn[data-screen="${id}"]`);
  if (tab) tab.classList.add('active');

  if (id === 'screen-home')     renderHome();
  if (id === 'screen-deck')     renderDeck();
  if (id === 'screen-settings') renderSettings();
  if (id === 'screen-add')      switchAddTab('single');
}

// ═══════════════════════════════════════════════════════
//  HOME screen
// ═══════════════════════════════════════════════════════
function renderHome() {
  const due   = dueCards(cards);
  const total = cards.length;
  const mastered = cards.filter(c => c.repetitions >= 5).length;

  document.getElementById('home-due-count').textContent  = due.length;
  document.getElementById('home-due-label').textContent  = due.length === 1 ? 'card due today' : 'cards due today';
  const s = cfg.streak || 0;
  document.getElementById('home-streak').textContent = `🔥 ${s} day${s === 1 ? '' : 's'}`;
  document.getElementById('stat-total').textContent      = total;
  document.getElementById('stat-mastered').textContent   = mastered;
  document.getElementById('stat-due').textContent        = due.length;

  const btn = document.getElementById('start-review-btn');
  if (due.length > 0) {
    btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg> Start Review (${due.length})`;
    btn.disabled = false;
    btn.classList.remove('done');
  } else {
    btn.textContent = '✓  All caught up!';
    btn.disabled = true;
    btn.classList.add('done');
  }

  // CEFR breakdown
  const wrap = document.getElementById('cefr-breakdown');
  wrap.innerHTML = '';
  let hasAny = false;
  CEFR_LEVELS.forEach(level => {
    const count = cards.filter(c => c.cefr === level).length;
    if (!count) return;
    hasAny = true;
    const pct = Math.round(count / Math.max(total, 1) * 100);
    wrap.innerHTML += `
      <div class="cefr-row-item">
        <span class="cefr-pill" style="background:${CEFR_COLOR[level]}">${level}</span>
        <span class="cefr-row-name">${cefrName(level)}</span>
        <span class="cefr-row-count">${count}</span>
        <div class="cefr-bar-bg">
          <div class="cefr-bar" style="width:${pct}%;background:${CEFR_COLOR[level]}"></div>
        </div>
      </div>`;
  });
  document.getElementById('cefr-panel').style.display = hasAny ? 'block' : 'none';
}

function cefrName(l) {
  return { A1:'Beginner', A2:'Elementary', B1:'Intermediate', B2:'Upper-Intermediate', C1:'Advanced', C2:'Mastery' }[l] || l;
}

// ═══════════════════════════════════════════════════════
//  REVIEW screen
// ═══════════════════════════════════════════════════════
function startReview() {
  session.queue    = dueCards(cards);
  session.index    = 0;
  session.flipped  = false;
  session.reviewed = 0;
  showScreen('screen-review');
  renderReviewCard();
}

function renderReviewCard() {
  const total = session.queue.length;

  if (session.index >= total) {
    // session complete
    document.getElementById('review-session').classList.add('hidden');
    document.getElementById('review-done').classList.remove('hidden');
    document.getElementById('done-count').textContent =
      `You reviewed ${session.reviewed} card${session.reviewed === 1 ? '' : 's'}. Great work!`;
    updateStreak();
    return;
  }

  document.getElementById('review-session').classList.remove('hidden');
  document.getElementById('review-done').classList.add('hidden');

  const card = session.queue[session.index];
  const pct  = Math.round(session.index / total * 100);

  document.getElementById('review-progress-fill').style.width = pct + '%';
  document.getElementById('review-counter').textContent = `${session.index + 1} / ${total}`;

  // front / back depend on study direction
  const svFirst = (cfg.studyDirection || 'sv-en') === 'sv-en';
  const frontWord = svFirst ? card.swedish  : card.english;
  const backWord  = svFirst ? card.english  : card.swedish;
  const frontCtx  = svFirst ? card.sourceContext : '';
  const backExSv  = svFirst ? card.exampleSentenceSV : card.exampleSentenceEN;
  const backExEn  = svFirst ? card.exampleSentenceEN : card.exampleSentenceSV;

  document.getElementById('card-sv').textContent = frontWord;
  document.getElementById('card-ctx').textContent = frontCtx ? `"${frontCtx}"` : '';
  document.getElementById('card-ctx').style.display = frontCtx ? '' : 'none';

  // back face
  document.getElementById('card-en').textContent = backWord;
  document.getElementById('card-ex-sv').textContent = backExSv;
  document.getElementById('card-ex-en').textContent = backExEn;
  document.getElementById('card-ex-sv').style.display = card.exampleSentenceSV ? '' : 'none';
  document.getElementById('card-sep').style.display = card.exampleSentenceSV ? '' : 'none';
  document.getElementById('card-ex-en').style.display = card.exampleSentenceEN ? '' : 'none';

  // CEFR badge on both faces
  ['card-front-tag','card-back-tag'].forEach(id => {
    const el = document.getElementById(id);
    el.textContent = card.cefr;
    el.style.background = CEFR_COLOR[card.cefr] || '#0ea5e9';
  });

  // reset flip
  session.flipped = false;
  document.getElementById('flip-card').classList.remove('flipped');
  document.getElementById('rating-section').classList.add('hidden');
  document.getElementById('tap-hint').classList.remove('hidden');
}

function flipCard() {
  if (session.flipped) return;
  session.flipped = true;
  document.getElementById('flip-card').classList.add('flipped');
  document.getElementById('tap-hint').classList.add('hidden');
  document.getElementById('rating-section').classList.remove('hidden');
}

function rateCard(rating) {
  const card = session.queue[session.index];
  const idx  = cards.findIndex(c => c.id === card.id);
  if (idx !== -1) {
    cards[idx] = sm2Review({ ...cards[idx] }, rating);
    saveCards(cards);
  }
  session.reviewed++;
  session.index++;

  // quick slide-out animation
  const fc = document.getElementById('flip-card');
  fc.style.transition = 'transform .2s ease, opacity .2s ease';
  fc.style.transform  = 'translateX(-60px)';
  fc.style.opacity    = '0';
  setTimeout(() => {
    fc.style.transition = 'none';
    fc.style.transform  = '';
    fc.style.opacity    = '';
    setTimeout(() => {
      fc.style.transition = '';
      renderReviewCard();
    }, 30);
  }, 220);
}

// ═══════════════════════════════════════════════════════
//  DECK screen
// ═══════════════════════════════════════════════════════
let deckFilter = { search: '', cefr: null };

function renderDeck() {
  let filtered = cards.filter(c => {
    const q = deckFilter.search.toLowerCase();
    const matchSearch = !q || c.swedish.toLowerCase().includes(q) || c.english.toLowerCase().includes(q);
    const matchCEFR   = !deckFilter.cefr || c.cefr === deckFilter.cefr;
    return matchSearch && matchCEFR;
  }).sort((a,b) => new Date(b.createdAt) - new Date(a.createdAt));

  // title
  document.getElementById('deck-title').textContent = `Deck (${cards.length})`;

  // chips
  document.querySelectorAll('.chip').forEach(c => {
    c.classList.toggle('active', c.dataset.cefr === (deckFilter.cefr || 'all'));
  });

  const list = document.getElementById('deck-list');
  const empty = document.getElementById('deck-empty');

  if (filtered.length === 0) {
    list.innerHTML = '';
    empty.classList.remove('hidden');
  } else {
    empty.classList.add('hidden');
    list.innerHTML = filtered.map(card => {
      const due  = isDue(card);
      const days = Math.round((new Date(card.nextReviewDate) - new Date()) / 86400000);
      const meta = due ? '<span class="deck-card-due">Due now</span>'
                       : `<span class="deck-card-next">in ${days}d</span>`;
      return `
        <div class="deck-card" data-id="${card.id}">
          <div style="flex:1;min-width:0">
            <div class="deck-card-sv">${esc(card.swedish)}</div>
            <div class="deck-card-en">${esc(card.english)}</div>
          </div>
          <div class="deck-card-right">
            <span class="deck-card-badge" style="background:${CEFR_COLOR[card.cefr]||'#0ea5e9'}">${card.cefr}</span>
            ${meta}
          </div>
          <button class="del-btn" onclick="deleteCard('${card.id}')">
            <svg width="15" height="15" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
              <path stroke-linecap="round" stroke-linejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/>
            </svg>
          </button>
        </div>`;
    }).join('');
  }
}

function deleteCard(id) {
  if (!confirm('Delete this flashcard?')) return;
  cards = cards.filter(c => c.id !== id);
  saveCards(cards);
  renderDeck();
  showToast('Card deleted');
}

// ═══════════════════════════════════════════════════════
//  ADD screen
// ═══════════════════════════════════════════════════════
let addMode = 'single';
let batchWordList  = [];
let cameraWordList = [];
let csvRowList     = [];

const ADD_PANELS = ['single', 'batch', 'camera', 'csv'];

function switchAddTab(mode) {
  addMode = mode;
  document.querySelectorAll('.tab-toggle-btn').forEach(t =>
    t.classList.toggle('active', t.dataset.tab === mode)
  );
  ADD_PANELS.forEach(p => {
    const el = document.getElementById(`add-${p}-panel`);
    if (el) el.classList.toggle('hidden', p !== mode);
  });
}

async function doTranslate() {
  const word = document.getElementById('single-word').value.trim();
  if (!word) return;
  if (!cfg.apiKey) { showToast('Add your API key in Settings first'); return; }

  setLoading('single-loading', true);
  document.getElementById('translate-result').classList.remove('show');
  try {
    const res = await translateWord(word, cfg.apiKey);
    document.getElementById('tr-sv').textContent      = res.swedish;
    document.getElementById('tr-en').textContent      = res.english;
    document.getElementById('tr-cefr').textContent    = `CEFR: ${res.cefr}`;
    document.getElementById('tr-cefr').style.background = CEFR_COLOR[res.cefr] || '#6366f1';
    document.getElementById('tr-ex').textContent      = res.example_sentence_sv
      ? `"${res.example_sentence_sv}" — "${res.example_sentence_en}"` : '';
    document.getElementById('translate-result').classList.add('show');
    document.getElementById('translate-result').dataset.card = JSON.stringify(res);
  } catch(e) {
    showToast(e.message);
  }
  setLoading('single-loading', false);
}

function saveTranslatedCard() {
  const raw = document.getElementById('translate-result').dataset.card;
  if (!raw) return;
  const res = JSON.parse(raw);
  const card = makeCard(res.swedish, res.english, res.cefr, res.example_sentence_sv, res.example_sentence_en);
  cards.push(card);
  saveCards(cards);
  showToast('Card added to deck ✓');
  document.getElementById('single-word').value = '';
  document.getElementById('translate-result').classList.remove('show');
}

async function doBatchExtract() {
  const text = document.getElementById('batch-text').value.trim();
  if (!text) return;
  if (!cfg.apiKey) { showToast('Add your API key in Settings first'); return; }

  setLoading('batch-loading', true);
  document.getElementById('word-selection').classList.add('hidden');
  document.getElementById('batch-save-btn').classList.add('hidden');
  batchWordList = [];
  try {
    const words = await extractVocabulary(text, cfg.targetCEFR, cfg.apiKey);
    batchWordList = words.map(w => ({ ...w, selected: true }));
    renderWordSelection();
    document.getElementById('word-selection').classList.remove('hidden');
    document.getElementById('batch-save-btn').classList.remove('hidden');
  } catch(e) {
    showToast(e.message);
  }
  setLoading('batch-loading', false);
}

// shared word-list renderer
function renderWordList(listId, countId, saveBtnId, wordArr, toggleFn) {
  const list = document.getElementById(listId);
  list.innerHTML = wordArr.map((w,i) => `
    <div class="word-item ${w.selected ? 'on' : ''}" onclick="${toggleFn}(${i})">
      <svg class="word-check" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
      <div style="flex:1;min-width:0">
        <div class="word-sv">${esc(w.swedish)}</div>
        <div class="word-en">${esc(w.english)}
          <span class="deck-card-badge" style="background:${CEFR_COLOR[w.cefr]||'#0ea5e9'};font-size:9px;padding:1px 6px;border-radius:4px;margin-left:4px;vertical-align:middle">${w.cefr||'?'}</span>
        </div>
      </div>
    </div>`).join('');
  const n = wordArr.filter(w => w.selected).length;
  if (countId) document.getElementById(countId).textContent = `${n} of ${wordArr.length} selected`;
  if (saveBtnId) {
    const btn = document.getElementById(saveBtnId);
    btn.textContent = `Add ${n} card${n===1?'':'s'} to deck`;
    btn.disabled = n === 0;
    btn.classList.toggle('hidden', wordArr.length === 0);
  }
}

function renderWordSelection() {
  renderWordList('word-list', 'word-sel-count', 'batch-save-btn', batchWordList, 'toggleBatchWord');
  document.getElementById('word-selection').classList.toggle('hidden', batchWordList.length === 0);
}

function toggleBatchWord(i) {
  batchWordList[i].selected = !batchWordList[i].selected;
  renderWordSelection();
}

function saveBatchCards() {
  const selected = batchWordList.filter(w => w.selected);
  selected.forEach(w => {
    if (!cards.find(c => c.swedish.toLowerCase() === w.swedish.toLowerCase()))
      cards.push(makeCard(w.swedish, w.english, w.cefr));
  });
  saveCards(cards);
  showToast(`${selected.length} card${selected.length===1?'':'s'} added ✓`);
  document.getElementById('batch-text').value = '';
  document.getElementById('word-selection').classList.add('hidden');
  document.getElementById('batch-save-btn').classList.add('hidden');
  batchWordList = [];
}

// ═══════════════════════════════════════════════════════
//  CAMERA / Image scan
// ═══════════════════════════════════════════════════════
let selectedImageBase64 = null;
let selectedImageMime   = null;

function onImageSelected(input) {
  const file = input.files[0];
  if (!file) return;
  selectedImageMime = file.type || 'image/jpeg';
  const reader = new FileReader();
  reader.onload = e => {
    // strip "data:image/...;base64," prefix
    selectedImageBase64 = e.target.result.split(',')[1];
    document.getElementById('camera-preview-img').src = e.target.result;
    document.getElementById('camera-source-btns').classList.add('hidden');
    document.getElementById('camera-preview-wrap').classList.remove('hidden');
    // show cefr selector
    document.getElementById('camera-cefr-label').style.display = '';
    document.getElementById('camera-cefr-select').classList.remove('hidden');
    // reset previous results
    document.getElementById('camera-word-selection').classList.add('hidden');
    document.getElementById('camera-save-btn').classList.add('hidden');
    cameraWordList = [];
  };
  reader.readAsDataURL(file);
  input.value = ''; // allow re-selecting same file
}

function resetCamera() {
  selectedImageBase64 = null;
  selectedImageMime   = null;
  document.getElementById('camera-source-btns').classList.remove('hidden');
  document.getElementById('camera-preview-wrap').classList.add('hidden');
  document.getElementById('camera-cefr-label').style.display = 'none';
  document.getElementById('camera-cefr-select').classList.add('hidden');
  document.getElementById('camera-word-selection').classList.add('hidden');
  document.getElementById('camera-save-btn').classList.add('hidden');
  cameraWordList = [];
}

async function doImageExtract() {
  if (!selectedImageBase64) return;
  if (!cfg.apiKey) { showToast('Add your API key in Settings first'); return; }

  setLoading('camera-loading', true);
  document.getElementById('camera-word-selection').classList.add('hidden');
  document.getElementById('camera-save-btn').classList.add('hidden');
  cameraWordList = [];

  try {
    const level = cfg.targetCEFR || 'B1';
    const prompt = `You are a Swedish language teacher. Look at this image and find all readable Swedish words. Extract unique Swedish words at CEFR level ${level} or below. Ignore proper nouns, numbers, punctuation. Return ONLY a valid JSON array (no markdown): [{"swedish":"...","english":"...","cefr":"A1|A2|B1|B2|C1|C2"}]`;

    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': cfg.apiKey,
        'anthropic-version': '2023-06-01',
        'anthropic-dangerous-direct-browser-access': 'true'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        messages: [{
          role: 'user',
          content: [
            { type: 'image', source: { type: 'base64', media_type: selectedImageMime, data: selectedImageBase64 } },
            { type: 'text', text: prompt }
          ]
        }]
      })
    });

    if (res.status === 429) throw new Error('Rate limited — please wait a moment.');
    if (!res.ok) throw new Error(`API error ${res.status}`);
    const data = await res.json();
    const raw  = data.content[0].text.trim();
    cameraWordList = parseJSON(raw).map(w => ({ ...w, selected: true }));

    renderCameraWordList();
  } catch(e) {
    showToast(e.message);
  }
  setLoading('camera-loading', false);
}

function renderCameraWordList() {
  renderWordList('camera-word-list', 'camera-sel-count', 'camera-save-btn', cameraWordList, 'toggleCameraWord');
  document.getElementById('camera-word-selection').classList.toggle('hidden', cameraWordList.length === 0);
  if (cameraWordList.length === 0) showToast('No Swedish words found in this image');
}

function toggleCameraWord(i) {
  cameraWordList[i].selected = !cameraWordList[i].selected;
  renderCameraWordList();
}

function saveCameraCards() {
  const selected = cameraWordList.filter(w => w.selected);
  selected.forEach(w => {
    if (!cards.find(c => c.swedish.toLowerCase() === w.swedish.toLowerCase()))
      cards.push(makeCard(w.swedish, w.english, w.cefr));
  });
  saveCards(cards);
  showToast(`${selected.length} card${selected.length===1?'':'s'} added ✓`);
  resetCamera();
}

// ═══════════════════════════════════════════════════════
//  CSV import
// ═══════════════════════════════════════════════════════
function onCSVSelected(input) {
  const file = input.files[0];
  if (!file) return;
  const reader = new FileReader();
  reader.onload = e => parseCSVFile(e.target.result);
  reader.readAsText(file, 'UTF-8');
  input.value = '';
}

// raw parsed CSV data before column mapping
let csvRawRows    = [];   // array of string[] (one per row)
let csvHeaders    = [];   // column names (from header row or Col 1/2/3...)
let csvFrontIdx   = 0;
let csvBackIdx    = 1;
let csvCEFRIdx    = -1;

function parseCSVFile(text) {
  const delim = text.includes('\t') ? '\t' : text.includes(';') ? ';' : ',';
  const lines  = text.trim().split(/\r?\n/).filter(l => l.trim());
  if (lines.length < 1) { showToast('Empty file'); return; }

  const firstCols = lines[0].split(delim).map(c => c.trim().replace(/^"|"$/g,''));
  const hasHeader = firstCols.some(c =>
    ['swedish','english','sv','en','word','translation','front','back','question','answer','cefr']
      .includes(c.toLowerCase())
  );

  csvHeaders   = hasHeader
    ? firstCols.map(c => c.trim())
    : firstCols.map((_, i) => `Column ${i + 1}`);
  csvRawRows   = (hasHeader ? lines.slice(1) : lines)
    .map(l => l.split(delim).map(c => c.trim().replace(/^"|"$/g,'')))
    .filter(r => r.some(c => c));

  if (csvRawRows.length === 0) { showToast('No data rows found'); return; }

  // smart default column indices
  const lower = csvHeaders.map(h => h.toLowerCase());
  csvFrontIdx = lower.findIndex(h => ['swedish','sv','front','question','word'].includes(h));
  if (csvFrontIdx < 0) csvFrontIdx = 0;
  csvBackIdx  = lower.findIndex(h => ['english','en','back','answer','translation'].includes(h));
  if (csvBackIdx < 0) csvBackIdx = Math.min(1, csvHeaders.length - 1);
  csvCEFRIdx  = lower.findIndex(h => h === 'cefr');

  buildCSVColumnPicker();
  buildCSVRowList();
  renderCSVTable();
  document.getElementById('csv-preview').classList.remove('hidden');
  updateCSVSaveBtn();
}

function buildCSVColumnPicker() {
  const opts = csvHeaders.map((h,i) => `<option value="${i}">${esc(h)}</option>`).join('');
  const cefrOpts = `<option value="-1">— none —</option>` + csvHeaders.map((h,i) => `<option value="${i}">${esc(h)}</option>`).join('');

  document.getElementById('csv-col-picker').innerHTML = `
    <div class="col-picker-row">
      <div class="col-picker-item">
        <label class="field-label">Front of card</label>
        <select class="field-select" id="csv-front-col" onchange="csvFrontIdx=+this.value;refreshCSVTable()">
          ${opts}
        </select>
      </div>
      <div class="col-picker-swap" onclick="swapCSVCols()" title="Swap front/back">⇄</div>
      <div class="col-picker-item">
        <label class="field-label">Back of card</label>
        <select class="field-select" id="csv-back-col" onchange="csvBackIdx=+this.value;refreshCSVTable()">
          ${opts}
        </select>
      </div>
    </div>
    <div class="col-picker-row" style="margin-top:8px">
      <div class="col-picker-item" style="flex:1">
        <label class="field-label">CEFR column <span style="font-weight:400;text-transform:none">(optional)</span></label>
        <select class="field-select" id="csv-cefr-col" onchange="csvCEFRIdx=+this.value;refreshCSVTable()">
          ${cefrOpts}
        </select>
      </div>
    </div>`;

  document.getElementById('csv-front-col').value = String(csvFrontIdx);
  document.getElementById('csv-back-col').value  = String(csvBackIdx);
  document.getElementById('csv-cefr-col').value  = String(csvCEFRIdx);
  document.getElementById('csv-col-picker').classList.remove('hidden');
}

function swapCSVCols() {
  [csvFrontIdx, csvBackIdx] = [csvBackIdx, csvFrontIdx];
  document.getElementById('csv-front-col').value = String(csvFrontIdx);
  document.getElementById('csv-back-col').value  = String(csvBackIdx);
  refreshCSVTable();
}

function buildCSVRowList() {
  csvRowList = csvRawRows.map(row => ({
    swedish:  row[csvFrontIdx] || '',
    english:  row[csvBackIdx]  || '',
    cefr:     csvCEFRIdx >= 0 ? (row[csvCEFRIdx] || '?') : '?',
    selected: true
  }));
}

function refreshCSVTable() {
  buildCSVRowList();
  renderCSVTable();
  updateCSVSaveBtn();
}

function renderCSVTable() {
  const table = document.getElementById('csv-table');
  const frontLabel = csvHeaders[csvFrontIdx] || 'Front';
  const backLabel  = csvHeaders[csvBackIdx]  || 'Back';
  const cefrLabel  = csvCEFRIdx >= 0 ? (csvHeaders[csvCEFRIdx] || 'CEFR') : 'CEFR';
  table.innerHTML = `
    <thead><tr>
      <th><input type="checkbox" checked onchange="csvSelectAll(this.checked)"></th>
      <th>${esc(frontLabel)}</th><th>${esc(backLabel)}</th><th>${esc(cefrLabel)}</th>
    </tr></thead>
    <tbody>${csvRowList.map((r,i) => `
      <tr>
        <td><input type="checkbox" ${r.selected?'checked':''} onchange="csvRowList[${i}].selected=this.checked;updateCSVSaveBtn()"></td>
        <td><strong>${esc(r.swedish)}</strong></td>
        <td>${esc(r.english)}</td>
        <td>${r.cefr !== '?' ? `<span class="deck-card-badge" style="background:${CEFR_COLOR[r.cefr]||'#94a3b8'}">${r.cefr}</span>` : '<span style="color:var(--muted);font-size:12px">—</span>'}</td>
      </tr>`).join('')}
    </tbody>`;
}

function csvSelectAll(checked) {
  csvRowList.forEach(r => r.selected = checked);
  renderCSVTable();
  updateCSVSaveBtn();
}

function updateCSVSaveBtn() {
  const n   = csvRowList.filter(r => r.selected).length;
  const btn = document.getElementById('csv-save-btn');
  btn.textContent = `Import ${n} card${n===1?'':'s'}`;
  btn.disabled = n === 0;
  btn.classList.toggle('hidden', csvRowList.length === 0);
  document.getElementById('csv-sel-count').textContent = `${n} of ${csvRowList.length} selected`;
}

function saveCSVCards() {
  const selected = csvRowList.filter(r => r.selected);
  let added = 0;
  selected.forEach(r => {
    if (r.swedish && !cards.find(c => c.swedish.toLowerCase() === r.swedish.toLowerCase())) {
      const validCEFR = ['A1','A2','B1','B2','C1','C2'].includes(r.cefr) ? r.cefr : 'B1';
      cards.push(makeCard(r.swedish, r.english, validCEFR));
      added++;
    }
  });
  saveCards(cards);
  showToast(`${added} card${added===1?'':'s'} imported ✓`);
  // reset
  csvRowList = [];
  document.getElementById('csv-preview').classList.add('hidden');
  document.getElementById('csv-save-btn').classList.add('hidden');
}

// ═══════════════════════════════════════════════════════
//  SETTINGS screen
// ═══════════════════════════════════════════════════════
function renderSettings() {
  document.getElementById('api-key-input').value   = cfg.apiKey || '';
  document.getElementById('cefr-select').value     = cfg.targetCEFR || 'B1';
  document.getElementById('goal-select').value     = String(cfg.dailyGoal || 20);
  document.getElementById('direction-select').value = cfg.studyDirection || 'sv-en';
  document.getElementById('settings-total').textContent   = cards.length;
  document.getElementById('settings-due').textContent     = dueCards(cards).length;
  document.getElementById('settings-mastered').textContent = cards.filter(c=>c.repetitions>=5).length;
  const sk = cfg.streak || 0;
  document.getElementById('settings-streak').textContent  = `${sk} day${sk === 1 ? '' : 's'}`;
}

function saveApiKey() {
  cfg.apiKey = document.getElementById('api-key-input').value.trim();
  saveConfig(cfg);
  showToast('API key saved ✓');
}

function saveCEFR() {
  cfg.targetCEFR = document.getElementById('cefr-select').value;
  saveConfig(cfg);
}

function saveGoal() {
  cfg.dailyGoal = parseInt(document.getElementById('goal-select').value);
  saveConfig(cfg);
}

function saveStudyDirection() {
  cfg.studyDirection = document.getElementById('direction-select').value;
  saveConfig(cfg);
}

function toggleKeyVisible() {
  const inp = document.getElementById('api-key-input');
  inp.type = inp.type === 'password' ? 'text' : 'password';
}

function resetAllCards() {
  if (!confirm(`Delete all ${cards.length} flashcards? This cannot be undone.`)) return;
  cards = [];
  saveCards(cards);
  cfg.streak = 0;
  cfg.lastReviewDay = null;
  saveConfig(cfg);
  renderSettings();
  showToast('All cards deleted');
}

// ── Sample data ───────────────────────────────────────
function loadSampleCards() {
  if (cards.length > 0) { showToast('Deck already has cards'); return; }
  const samples = [
    ['hej',       'hello',      'A1', 'Hej! Hur mår du?',        'Hello! How are you?'],
    ['tack',      'thank you',  'A1', 'Tack så mycket!',          'Thank you so much!'],
    ['kärlek',    'love',       'A1', 'Kärlek är viktig.',        'Love is important.'],
    ['vacker',    'beautiful',  'A2', 'Det är en vacker dag.',    'It is a beautiful day.'],
    ['framtid',   'future',     'B1', 'Vi tänker på framtiden.',  'We think about the future.'],
    ['frihet',    'freedom',    'B1', 'Frihet är ovärderlig.',    'Freedom is invaluable.'],
    ['äventyr',   'adventure',  'B2', 'Ett stort äventyr väntar.','A great adventure awaits.'],
    ['hållbarhet','sustainability','C1','Hållbarhet är viktigt.',  'Sustainability is important.'],
    ['välmående', 'well-being', 'C1', 'Välmående är ett mål.',    'Well-being is a goal.'],
    ['förtroende','trust',      'B2', 'Förtroende tar tid.',      'Trust takes time.'],
  ];
  samples.forEach(([sv,en,cefr,exSV,exEN]) => cards.push(makeCard(sv,en,cefr,exSV,exEN)));
  saveCards(cards);
  showToast(`${samples.length} sample cards loaded ✓`);
  renderHome();
}

// ── Utility ───────────────────────────────────────────
function esc(s) {
  return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function setLoading(id, on) {
  document.getElementById(id).classList.toggle('show', on);
}

let toastTimer;
function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('show'), 2800);
}

// ── Boot ──────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  showScreen('screen-home');
});
