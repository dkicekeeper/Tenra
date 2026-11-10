#!/usr/bin/env python3
"""Builds the public site's landing pages and calculators into docs/public.

    python3 scripts/build_site.py          # write the pages
    python3 scripts/build_site.py --check  # fail when a committed page is out of date

The pages are plain HTML so search engines read every word; the numbers come from
docs/public/assets/calc.js. Texts live in scripts/site_strings.json, one block per language.
The legal pages (privacy-policy, terms-of-use, support) are written by hand and are not touched.
Why the site has calculators: docs/plan-growth.md.
"""
import html
import io
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "public"
BASE = "https://dkicekeeper.github.io/Tenra/"
APP_ID = "6761530361"
STORE = f"https://apps.apple.com/app/id{APP_ID}"
# The "Deposits and loans" custom product page (docs/promotion-plan.md §7).
STORE_DEPOSITS_LOANS = f"{STORE}?ppid=23fa027e-1341-4344-8d3e-e5567b713dda"
LANGS = ["ru", "kk", "en"]
PAGES = ["index", "deposit-calculator", "loan-calculator"]
CURRENCIES = ["₸", "₽", "$", "€"]
# What the forms open with: amount, rate, term in months.
DEFAULTS = {
    "deposit-calculator": {"₸": ("1 000 000", "15", "12"), "$": ("10 000", "4.5", "12")},
    "loan-calculator": {"₸": ("1 000 000", "20", "24"), "$": ("10 000", "9", "24")},
}


def path_of(lang, page):
    """English sits at the root (the address the App Store links to), the rest in a folder."""
    name = "index.html" if page == "index" else f"{page}.html"
    return name if lang == "en" and page == "index" else f"{lang}/{name}"


def fill(template, values):
    def value(match):
        return str(values[match.group(1)])
    return re.sub(r"\{\{(\w+)\}\}", value, template)


def esc(text):
    return html.escape(text, quote=True)


SHELL = """<!DOCTYPE html>
<html lang="{{lang}}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{title}}</title>
    <meta name="description" content="{{description}}">
    <link rel="canonical" href="{{canonical}}">
{{alternates}}
    <meta name="apple-itunes-app" content="app-id={{app_id}}">
    <meta property="og:title" content="{{title}}">
    <meta property="og:description" content="{{description}}">
    <meta property="og:type" content="website">
    <meta property="og:url" content="{{canonical}}">
    <link rel="stylesheet" href="{{up}}assets/site.css">
{{jsonld}}
</head>
<body>
<div class="wrap">
    <header class="top">
        <a class="brand" href="{{home}}">Tenra</a>
        <nav class="langs" aria-label="{{langs_label}}">{{langs}}</nav>
    </header>
    <main>
{{main}}
    </main>
    <footer>
        {{footer}}
    </footer>
</div>
{{script}}
</body>
</html>
"""

CTA = """        <section class="card cta">
            <h2>{{cta_title}}</h2>
            <p>{{cta_text}}</p>
            <p><a class="button" href="{{store}}">{{cta_button}}</a></p>
            <p class="note">{{cta_note}}</p>
        </section>"""

COMMON_FIELDS = """                    <div class="field">
                        <label for="amount">{{f_amount}}</label>
                        <input id="amount" name="amount" inputmode="decimal" autocomplete="off" value="{{d_amount}}">
                    </div>
                    <div class="field">
                        <label for="currency">{{f_currency}}</label>
                        <select id="currency" name="currency">{{currency_options}}</select>
                    </div>
                    <div class="field">
                        <label for="rate">{{f_rate}}</label>
                        <input id="rate" name="rate" inputmode="decimal" autocomplete="off" value="{{d_rate}}">
                    </div>
                    <div class="field">
                        <label for="term">{{f_term}}</label>
                        <input id="term" name="term" inputmode="numeric" autocomplete="off" value="{{d_term}}">
                    </div>
                    <div class="field wide">
                        <label for="unit">{{f_unit}}</label>
                        <select id="unit" name="unit"><option value="months" selected>{{u_months}}</option><option value="years">{{u_years}}</option></select>
                    </div>"""

DEPOSIT = """        <h1>{{h1}}</h1>
        <p class="lead">{{lead}}</p>
        <form data-calc="deposit" novalidate>
            <section class="card">
                <div class="fields">
""" + COMMON_FIELDS + """
                    <div class="field wide">
                        <label for="topup">{{f_topup}}</label>
                        <input id="topup" name="topup" inputmode="decimal" autocomplete="off" value="0">
                    </div>
                    <label class="check field wide"><input type="checkbox" name="capitalize" checked> {{f_capitalize}}</label>
                </div>
            </section>
            <section class="card" aria-live="polite">
                <div class="results">
                    <div class="result main wide"><div class="label">{{r_total}}</div><div class="value" id="out-total"></div></div>
                    <div class="result"><div class="label">{{r_interest}}</div><div class="value good" id="out-interest"></div></div>
                    <div class="result"><div class="label">{{r_effective}}</div><div class="value" id="out-effective"></div></div>
                    <div class="result wide"><div class="label">{{r_contributed}}</div><div class="value" id="out-contributed"></div></div>
                </div>
            </section>
        </form>
        <p class="note">{{disclaimer}}</p>
{{cta}}
{{article}}
        <h2>{{other_title}}</h2>
        <div class="links">{{other_links}}</div>"""

LOAN = """        <h1>{{h1}}</h1>
        <p class="lead">{{lead}}</p>
        <form data-calc="loan" novalidate>
            <section class="card">
                <div class="fields">
""" + COMMON_FIELDS + """
                    <div class="field wide">
                        <label for="type">{{f_type}}</label>
                        <select id="type" name="type"><option value="annuity" selected>{{t_annuity}}</option><option value="diff">{{t_diff}}</option></select>
                    </div>
                    <div class="field wide">
                        <label for="extra">{{f_extra}}</label>
                        <input id="extra" name="extra" inputmode="decimal" autocomplete="off" value="0">
                    </div>
                </div>
            </section>
            <section class="card" aria-live="polite">
                <div class="results">
                    <div class="result main wide">
                        <div class="label"><span id="label-payment">{{r_payment}}</span><span id="label-first" hidden>{{r_first}}</span></div>
                        <div class="value" id="out-payment"></div>
                    </div>
                    <div class="result wide" id="row-last" hidden><div class="label">{{r_last}}</div><div class="value" id="out-last"></div></div>
                    <div class="result"><div class="label">{{r_overpay}}</div><div class="value" id="out-interest"></div></div>
                    <div class="result"><div class="label">{{r_total}}</div><div class="value" id="out-total"></div></div>
                    <div class="result wide"><div class="label">{{r_months}}</div><div class="value" id="out-months"></div></div>
                    <div class="result wide" id="row-saved" hidden>
                        <div class="label">{{r_saved}}</div>
                        <div class="value good"><span id="out-saved"></span>, {{r_saved_months_before}} <span id="out-saved-months"></span> {{r_saved_months_after}}</div>
                    </div>
                </div>
            </section>
            <h2>{{schedule_title}}</h2>
            <div class="table-scroll">
                <table>
                    <thead><tr><th>{{c_month}}</th><th>{{c_payment}}</th><th>{{c_interest}}</th><th>{{c_principal}}</th><th>{{c_balance}}</th></tr></thead>
                    <tbody id="schedule"></tbody>
                </table>
            </div>
            <p><button type="button" class="button plain" id="show-all" hidden>{{show_all}}</button></p>
        </form>
        <p class="note">{{disclaimer}}</p>
{{cta}}
{{article}}
        <h2>{{other_title}}</h2>
        <div class="links">{{other_links}}</div>"""

INDEX = """        <h1>{{h1}}</h1>
        <p class="lead">{{lead}}</p>
        <p><a class="button" href="{{store}}">{{cta_button}}</a></p>
        <p class="note">{{cta_note}}</p>
{{article}}
        <h2>{{other_title}}</h2>
        <div class="links">{{other_links}}</div>"""


def article(blocks):
    """A page's long text: [["h2", text], ["p", text], ["formula", text], ["ul", [items]]]."""
    out = []
    for kind, body in blocks:
        if kind == "ul":
            items = "".join(f"<li>{esc(item)}</li>" for item in body)
            out.append(f"        <ul>{items}</ul>")
        elif kind == "formula":
            out.append(f'        <p class="formula">{esc(body)}</p>')
        else:
            out.append(f"        <{kind}>{esc(body)}</{kind}>")
    return "\n".join(out)


def faq_jsonld(faq):
    if not faq:
        return ""
    data = {
        "@context": "https://schema.org",
        "@type": "FAQPage",
        "mainEntity": [
            {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in faq
        ],
    }
    return '    <script type="application/ld+json">' + json.dumps(data, ensure_ascii=False) + "</script>"


def faq_blocks(title, faq):
    blocks = [["h2", title]] if faq else []
    for question, answer in faq:
        blocks += [["h3", question], ["p", answer]]
    return blocks


def build_page(strings, lang, page):
    s = strings[lang]
    common, p = s["common"], s[page]
    up = "" if path_of(lang, page).count("/") == 0 else "../"

    def href(other_lang, other_page):
        return up + path_of(other_lang, other_page).replace("index.html", "") or "./"

    alternates = "\n".join(
        f'    <link rel="alternate" hreflang="{l}" href="{BASE}{path_of(l, page).replace("index.html", "")}">'
        for l in LANGS
    ) + f'\n    <link rel="alternate" hreflang="x-default" href="{BASE}{path_of("en", page).replace("index.html", "")}">'
    langs = "".join(
        f'<a href="{href(l, page)}" lang="{l}"' + (' aria-current="true"' if l == lang else "") + f">{esc(strings[l]['common']['lang_name'])}</a>"
        for l in LANGS
    )
    others = "".join(
        f'<a href="{href(lang, other)}"><strong>{esc(s[other]["card_title"])}</strong><span>{esc(s[other]["card_text"])}</span></a>'
        for other in PAGES if other != page and other != "index"
    )
    footer = " ".join([
        f'<a href="{href(lang, "index")}">Tenra</a>',
        f'<a href="{up}support.html">{esc(common["support"])}</a>',
        f'<a href="{up}privacy-policy.html">{esc(common["privacy"])}</a>',
        f'<a href="{up}terms-of-use.html">{esc(common["terms"])}</a>',
    ])

    store = STORE if page == "index" else STORE_DEPOSITS_LOANS
    values = {k: esc(v) for k, v in {**common, **p}.items() if isinstance(v, str)}
    values.update({
        "store": store,
        "currency_options": "".join(
            f'<option{" selected" if c == common["currency"] else ""}>{c}</option>' for c in CURRENCIES
        ),
        "other_links": others,
    })
    if page in DEFAULTS:
        values["d_amount"], values["d_rate"], values["d_term"] = DEFAULTS[page][common["currency"]]
    values["cta"] = fill(CTA, values) if page != "index" else ""
    values["article"] = article(p["article"] + faq_blocks(common["faq_title"], p.get("faq", [])))
    main = fill({"index": INDEX, "deposit-calculator": DEPOSIT, "loan-calculator": LOAN}[page], values)

    return fill(SHELL, {
        "lang": lang,
        "title": esc(p["title"]),
        "description": esc(p["description"]),
        "canonical": BASE + path_of(lang, page).replace("index.html", ""),
        "alternates": alternates,
        "app_id": APP_ID,
        "up": up,
        "jsonld": faq_jsonld(p.get("faq", [])),
        "home": href(lang, "index"),
        "langs_label": esc(common["langs_label"]),
        "langs": langs,
        "main": main,
        "footer": footer,
        "script": "" if page == "index" else f'<script src="{up}assets/calc.js"></script>',
    })


def sitemap():
    urls = "\n".join(
        f"  <url><loc>{BASE}{path_of(l, p).replace('index.html', '')}</loc></url>" for p in PAGES for l in LANGS
    )
    return f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n{urls}\n</urlset>\n'


def main():
    check = "--check" in sys.argv
    with io.open(ROOT / "scripts" / "site_strings.json", encoding="utf-8") as file:
        strings = json.load(file)
    files = {path_of(l, p): build_page(strings, l, p) for l in LANGS for p in PAGES}
    files["sitemap.xml"] = sitemap()
    stale = []
    for name, text in files.items():
        target = OUT / name
        if check:
            if not target.exists() or target.read_text(encoding="utf-8") != text:
                stale.append(name)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with io.open(target, "w", encoding="utf-8") as file:
            file.write(text)
    if stale:
        sys.exit("Out of date, run python3 scripts/build_site.py: " + ", ".join(stale))
    print(("Checked" if check else "Wrote") + f" {len(files)} files")


if __name__ == "__main__":
    main()
