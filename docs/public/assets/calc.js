// Tenra's public calculators (docs/public, built by scripts/build_site.py).
// No strings here: every label is in the page, this file only puts numbers into it.
// The math is exported for scripts/test_site_calc.js.
(function (root) {
    "use strict";

    /// A deposit by months: interest on the balance each month, a top-up after every month
    /// but the last. With capitalization the interest joins the balance; without it is paid out.
    function deposit(amount, ratePercent, months, topUp, capitalize) {
        var monthly = ratePercent / 100 / 12;
        var balance = amount, interest = 0, contributed = amount;
        for (var m = 1; m <= months; m++) {
            var accrued = balance * monthly;
            interest += accrued;
            if (capitalize) balance += accrued;
            if (m < months && topUp > 0) { balance += topUp; contributed += topUp; }
        }
        return {
            interest: interest,
            total: contributed + interest,
            contributed: contributed,
            effectiveRate: capitalize ? (Math.pow(1 + monthly, 12) - 1) * 100 : ratePercent
        };
    }

    /// A loan's schedule. `kind` is "annuity" (equal payments) or "diff" (equal principal).
    /// `extra` is paid on top every month and shortens the term. A zero rate is an instalment plan.
    function loan(amount, ratePercent, months, kind, extra) {
        var monthly = ratePercent / 100 / 12;
        var annuity = monthly === 0 ? amount / months : amount * monthly / (1 - Math.pow(1 + monthly, -months));
        var principalPart = amount / months;
        var balance = amount, interestTotal = 0, rows = [];
        // 1200 months is past any term the form allows; it only guards the loop.
        for (var m = 1; balance > 0.005 && m <= 1200; m++) {
            var interest = balance * monthly;
            var principal = (kind === "diff" ? principalPart : annuity - interest) + extra;
            if (principal > balance) principal = balance;
            balance -= principal;
            interestTotal += interest;
            rows.push({ month: m, payment: principal + interest, interest: interest, principal: principal, balance: balance < 0.005 ? 0 : balance });
        }
        return {
            payment: rows.length ? rows[0].payment - extra : 0,
            lastPayment: rows.length ? rows[rows.length - 1].payment : 0,
            interest: interestTotal,
            total: amount + interestTotal,
            months: rows.length,
            rows: rows
        };
    }

    root.TenraCalc = { deposit: deposit, loan: loan };
    if (typeof module !== "undefined") module.exports = root.TenraCalc;
    if (typeof document === "undefined") return;

    var form = document.querySelector("[data-calc]");
    if (!form) return;
    var kind = form.getAttribute("data-calc");
    var lang = document.documentElement.lang || "en";
    // Kazakh writes numbers as Russian does, and not every browser has its own data for it.
    var numbers = lang === "kk" ? "ru" : lang;
    var money = new Intl.NumberFormat(numbers, { maximumFractionDigits: 0 });
    var percent = new Intl.NumberFormat(numbers, { minimumFractionDigits: 2, maximumFractionDigits: 2 });

    function field(name) { return form.querySelector("[name=" + name + "]"); }

    /// "1 500 000", "1,5" and "1.5" all read as numbers; anything else is 0.
    function number(name, max) {
        var text = field(name).value.replace(/[\s  ]/g, "").replace(",", ".");
        var value = parseFloat(text);
        if (!isFinite(value) || value < 0) return 0;
        return max !== undefined && value > max ? max : value;
    }

    function put(id, text) {
        var node = document.getElementById(id);
        if (node) node.textContent = text;
    }

    function show(id, visible) {
        var node = document.getElementById(id);
        if (node) node.hidden = !visible;
    }

    function amountText(value) {
        var text = money.format(Math.round(value)), symbol = field("currency").value;
        // English puts the symbol first; Russian and Kazakh put it after a space.
        return lang === "en" ? symbol + text : text + "\u00a0" + symbol;
    }

    function months() {
        return Math.max(1, Math.min(600, Math.round(number("term") * (field("unit").value === "years" ? 12 : 1))));
    }

    function renderDeposit() {
        var result = deposit(number("amount"), number("rate", 100), months(), number("topup"), field("capitalize").checked);
        put("out-total", amountText(result.total));
        put("out-interest", "+" + amountText(result.interest));
        put("out-contributed", amountText(result.contributed));
        put("out-effective", percent.format(result.effectiveRate) + " %");
    }

    var expanded = false;

    function renderLoan() {
        var amount = number("amount"), rate = number("rate", 100), term = months();
        var type = field("type").value, extra = number("extra");
        var result = loan(amount, rate, term, type, extra);
        var isDiff = type === "diff";

        put("out-payment", amountText(result.payment + extra));
        show("row-last", isDiff && result.months > 1);
        put("out-last", amountText(result.lastPayment));
        show("label-payment", !isDiff);
        show("label-first", isDiff);
        put("out-interest", amountText(result.interest));
        put("out-total", amountText(result.total));
        put("out-months", String(result.months));

        var base = extra > 0 ? loan(amount, rate, term, type, 0) : null;
        var saved = base ? base.interest - result.interest : 0;
        show("row-saved", saved > 0.5);
        if (base) {
            put("out-saved", amountText(saved));
            put("out-saved-months", String(base.months - result.months));
        }

        var body = document.getElementById("schedule");
        body.textContent = "";
        var limit = expanded ? result.rows.length : Math.min(12, result.rows.length);
        for (var i = 0; i < limit; i++) {
            var row = result.rows[i], line = document.createElement("tr");
            [String(row.month), money.format(Math.round(row.payment)), money.format(Math.round(row.interest)),
             money.format(Math.round(row.principal)), money.format(Math.round(row.balance))].forEach(function (text) {
                var cell = document.createElement("td");
                cell.textContent = text;
                line.appendChild(cell);
            });
            body.appendChild(line);
        }
        show("show-all", !expanded && result.rows.length > 12);
    }

    var render = kind === "deposit" ? renderDeposit : renderLoan;
    form.addEventListener("input", render);
    form.addEventListener("change", render);
    form.addEventListener("submit", function (event) { event.preventDefault(); });
    var all = document.getElementById("show-all");
    if (all) all.addEventListener("click", function () { expanded = true; render(); });
    render();
})(typeof window !== "undefined" ? window : globalThis);
