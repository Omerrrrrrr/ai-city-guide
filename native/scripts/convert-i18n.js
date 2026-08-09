#!/usr/bin/env node
// One-time conversion: mobile/src/i18n/locales/{en,tr,nb}.json (i18next,
// dot-path keys, CLDR plural suffixes) -> native/Piri/Sources/Resources/Localizable.xcstrings
// (Xcode String Catalog format). Re-run whenever the RN locale JSON changes
// upstream of the native rewrite catching up.
const fs = require('fs');
const path = require('path');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const LOCALES_DIR = path.join(REPO_ROOT, 'mobile', 'src', 'i18n', 'locales');
const OUT_PATH = path.join(REPO_ROOT, 'native', 'Piri', 'Sources', 'Resources', 'Localizable.xcstrings');

const LANGUAGES = ['en', 'tr', 'nb'];
const PLURAL_SUFFIXES = ['zero', 'one', 'two', 'few', 'many', 'other'];

function flatten(obj, prefix = '', out = {}) {
  for (const [k, v] of Object.entries(obj)) {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      flatten(v, key, out);
    } else {
      out[key] = String(v);
    }
  }
  return out;
}

function loadFlat(lang) {
  const raw = JSON.parse(fs.readFileSync(path.join(LOCALES_DIR, `${lang}.json`), 'utf8'));
  return flatten(raw);
}

const flatByLang = Object.fromEntries(LANGUAGES.map((l) => [l, loadFlat(l)]));

// Collect the union of all base keys, splitting out CLDR plural variants
// (`key_one`, `key_other`, ...) from their base key.
const baseKeys = new Set();
const pluralVariants = {}; // baseKey -> Set(suffix)

for (const lang of LANGUAGES) {
  for (const key of Object.keys(flatByLang[lang])) {
    const match = PLURAL_SUFFIXES.find((suffix) => key.endsWith(`_${suffix}`));
    if (match) {
      const base = key.slice(0, -(match.length + 1));
      pluralVariants[base] = pluralVariants[base] || new Set();
      pluralVariants[base].add(match);
      baseKeys.add(base);
    } else {
      baseKeys.add(key);
    }
  }
}

// i18next uses named `{{var}}` interpolation, which translators are free to
// reorder per language (e.g. `home.weatherBanner.fallback` puts {{city}}
// before {{description}} in Turkish but after it in English). A naive
// left-to-right `%@` conversion breaks that: `String(format:)` fills
// positional args in call-site order, so a reordered translation would
// receive the wrong value in the wrong slot. Instead every `{{var}}` becomes
// a POSIX positional specifier (`%1$@`, `%2$lld`, ...) numbered by the
// variable's index in the *English* source string — stable across
// languages regardless of where each translation places it — and Swift
// callers (`L()` in Localization.swift) always pass arguments in that same
// English-derived order.
function extractVarOrder(englishValue) {
  const order = [];
  for (const match of englishValue.matchAll(/\{\{(\w+)\}\}/g)) {
    if (!order.includes(match[1])) order.push(match[1]);
  }
  return order;
}

function convertInterpolation(value, varOrder) {
  return value.replace(/\{\{(\w+)\}\}/g, (_, name) => {
    const index = varOrder.indexOf(name) + 1; // positional specifiers are 1-based
    const spec = name === 'count' ? 'lld' : '@';
    return `%${index}$${spec}`;
  });
}

function stringUnit(value, varOrder) {
  return { stringUnit: { state: 'translated', value: convertInterpolation(value, varOrder) } };
}

const strings = {};

// Plural keys are emitted as flat `base.one` / `base.other` entries rather
// than xcstrings `variations.plural`, so every catalog key resolves via the
// same plain bare-key `String(localized:)` lookup used elsewhere — see
// `Localization.swift`'s `LPlural`, which picks the suffix itself (count == 1
// -> "one", English/Turkish/Norwegian Bokmal all only ever need those two
// CLDR categories, so this doesn't need real ICU plural-rule matching).
for (const base of Array.from(baseKeys).sort()) {
  const isPlural = Boolean(pluralVariants[base]);

  if (isPlural) {
    for (const suffix of pluralVariants[base]) {
      const englishValue = flatByLang.en[`${base}_${suffix}`] ?? flatByLang.en[`${base}_other`] ?? '';
      const varOrder = extractVarOrder(englishValue);
      const localizations = {};
      for (const lang of LANGUAGES) {
        const value = flatByLang[lang][`${base}_${suffix}`];
        if (value !== undefined) {
          localizations[lang] = stringUnit(value, varOrder);
        }
      }
      if (Object.keys(localizations).length > 0) {
        strings[`${base}.${suffix}`] = { localizations };
      }
    }
    continue;
  }

  const varOrder = extractVarOrder(flatByLang.en[base] ?? '');
  const localizations = {};
  for (const lang of LANGUAGES) {
    const value = flatByLang[lang][base];
    if (value !== undefined) {
      localizations[lang] = stringUnit(value, varOrder);
    }
  }
  if (Object.keys(localizations).length > 0) {
    strings[base] = { localizations };
  }
}

const catalog = {
  sourceLanguage: 'en',
  strings,
  version: '1.0',
};

fs.mkdirSync(path.dirname(OUT_PATH), { recursive: true });
fs.writeFileSync(OUT_PATH, JSON.stringify(catalog, null, 2) + '\n');

const pluralCount = Object.keys(pluralVariants).length;
console.log(`Wrote ${Object.keys(strings).length} keys (${pluralCount} pluralized) x ${LANGUAGES.length} languages to ${path.relative(REPO_ROOT, OUT_PATH)}`);
