// Regenerates test/golden.txt from upstream 0.0.5's own sources.
//
// This is the provenance of the parity test: rather than hand-transcribing what
// the original clock said, it replays upstream's Webview/index.js against a
// model of Webview/index.html and records the lit grid for all 1440 minutes.
// Both files are read straight out of git history — they were deleted by the
// port, so nothing here needs to be vendored.
//
//   node test/regenerate-golden.js > test/golden.txt
//
// Not wired into `just test`: node is not part of the pinned toolchain, and the
// golden file only changes if upstream's history does. `just test parity` reads
// the committed golden.

'use strict';
const { execFileSync } = require('child_process');

// The last commit before the modern-macOS port, i.e. upstream 0.0.5 as forked.
const UPSTREAM_REV = 'e1f0f163bd0f093e67474b48f541ae4b2e191587';

const html = execFileSync('git', ['show', `${UPSTREAM_REV}:Webview/index.html`], {
  encoding: 'utf8',
  maxBuffer: 8 << 20,
});

// --- Parse index.html into an ordered glyph list, each tagged with its words ---
const words = [];      // { classes: [...] }
const glyphs = [];     // { ch, ancestors: [wordIndex...] }
const stack = [];
// Upstream tags most spans <word> but a few <words> — a typo the CSS and JS
// never cared about, since both are matched by class. Words also nest (.minute
// inside .minutes), and `.on glyph` is a descendant selector, so a glyph lights
// if ANY ancestor is on.
const re = /<words? class="([^"]*)">|<\/words?>|<glyph>(.)<\/glyph>/g;
let m;
while ((m = re.exec(html)) !== null) {
  if (m[1] !== undefined) { words.push({ classes: m[1].split(/\s+/) }); stack.push(words.length - 1); }
  else if (m[2] !== undefined) glyphs.push({ ch: m[2], ancestors: stack.slice() });
  else stack.pop();
}
if (stack.length !== 0) throw new Error('unbalanced <word> tags');
if (glyphs.length !== 240) throw new Error(`expected 240 glyphs, got ${glyphs.length}`);

// --- Minimal DOM: only <word> elements ever carry the 'on' class ---
const on = new Set();
const first = cls => {
  const i = words.findIndex(w => w.classes.includes(cls));
  if (i < 0) throw new Error(`no element matches .${cls}`);
  return i;
};
const byClass = cls => words.map((w, i) => [w, i]).filter(([w]) => w.classes.includes(cls)).map(([, i]) => i);
const prefixElements = byClass('prefix');
const suffixElements = byClass('suffix');

// --- upstream Webview/index.js, transcribed ---
const setClockElOn = sel => on.add(first(sel.slice(1)));
const setPrefixElOn = n => on.add(prefixElements[n - 1]);
const setSuffixElOn = n => { if (parseInt(n, 10) === 13) n = 1; on.add(suffixElements[n - 1]); };

function setMinutes(minutes) {
  minutes = minutes.toString().split('');
  switch (parseInt(minutes[0], 10)) {
    case 2: setClockElOn('.twenty-minutes'); break;
    case 3: setClockElOn('.thirty-minutes'); break;
    case 4: setClockElOn('.forty-minutes'); break;
    case 5: setClockElOn('.fifty-minutes'); break;
  }
  if (minutes % 10 !== 0) setSuffixElOn(parseInt(minutes[1], 10));
}

function updateClock(hour, minutes) {
  on.clear();                                    // clearClock()
  if (hour >= 13) hour -= 12;
  if (parseInt(hour, 10) === 0) hour = 12;

  if (parseInt(minutes, 10) === 1) {
    setClockElOn('.one'); setClockElOn('.minute'); setClockElOn('.past'); setSuffixElOn(hour); return;
  }
  if (minutes <= 12 && minutes >= 2) {
    setPrefixElOn(minutes); setClockElOn('.minutes'); setClockElOn('.past'); setSuffixElOn(hour); return;
  }
  switch (minutes) {
    case 0:  setPrefixElOn(hour); setClockElOn('.oclock');    return;
    case 13: setPrefixElOn(hour); setClockElOn('.thirteen');  return;
    case 14: setPrefixElOn(hour); setClockElOn('.fourteen');  return;
    case 16: setPrefixElOn(hour); setClockElOn('.sixteen');   return;
    case 17: setPrefixElOn(hour); setClockElOn('.seventeen'); return;
    case 18: setPrefixElOn(hour); setClockElOn('.eighteen');  return;
    case 19: setPrefixElOn(hour); setClockElOn('.nineteen');  return;
    case 15: setClockElOn('.quarter'); setClockElOn('.past'); setSuffixElOn(hour); return;
    case 20: setClockElOn('.twenty');  setClockElOn('.past'); setSuffixElOn(hour); return;
    case 30: setClockElOn('.half');    setClockElOn('.past'); setSuffixElOn(hour); return;
    case 40: setClockElOn('.twenty');  setClockElOn('.to'); setSuffixElOn(hour + 1); return;
    case 45: setClockElOn('.quarter'); setClockElOn('.to'); setSuffixElOn(hour + 1); return;
    case 50: setClockElOn('.ten');     setClockElOn('.to'); setSuffixElOn(hour + 1); return;
    case 55: setClockElOn('.five');    setClockElOn('.to'); setSuffixElOn(hour + 1); return;
  }
  setPrefixElOn(hour);
  setMinutes(minutes);
}

// --- Emit: one line per minute, then the letter grid ---
const out = [];
for (let h = 0; h < 24; h++) {
  for (let mi = 0; mi < 60; mi++) {
    updateClock(h, mi);
    const lit = glyphs.map(g => g.ancestors.some(a => on.has(a)) ? '1' : '0').join('');
    out.push(`${String(h).padStart(2, '0')}:${String(mi).padStart(2, '0')} ${lit}`);
  }
}
out.push('LETTERS ' + glyphs.map(g => g.ch.toUpperCase()).join(''));
process.stdout.write(out.join('\n') + '\n');
