import type Anthropic from "@anthropic-ai/sdk";
import { describe, expect, it } from "vitest";
import { readConfig } from "../src/config";
import worker from "../src/index";
import { consumeValuation } from "../src/quota";
import {
  buildValuationParams,
  computeValuation,
  densestGroup,
  normalizeUrl,
  parseValuationRequest,
  REPORT_LISTINGS,
  REPORT_LISTINGS_TOOL,
  searchListings,
  searchResults,
  valuate,
  VALUATION_SYSTEM_PROMPT,
  valuationConfig,
  type AssetDescription,
  type Report,
  type ReportedListing,
} from "../src/valuation";
import { assertion, storedKey } from "./attest-helpers";
import fixture from "./fixtures/appattest.json";
import { MemoryKV } from "./helpers";

type Block = Anthropic.Beta.BetaContentBlock;
type Message = Anthropic.Beta.BetaMessage;

const now = new Date("2026-11-02T10:00:00Z");
const toolName = (tool: unknown) => (tool as { name?: string }).name;

const result = (url: string, title = "Listings") => ({ type: "web_search_result", url, title, page_age: null, encrypted_content: "e" });
const searched = (id: string, query: string, urls: string[]): Block[] =>
  [
    { type: "server_tool_use", id, name: "web_search", input: { query } },
    { type: "web_search_tool_result", tool_use_id: id, content: urls.map((u) => result(u)) },
  ] as unknown as Block[];
const reported = (input: Report): Block => ({ type: "tool_use", id: "toolu_1", name: REPORT_LISTINGS, input }) as unknown as Block;
const message = (content: Block[], stop_reason: string, searches = 1): Message =>
  ({
    id: "msg",
    type: "message",
    role: "assistant",
    model: "claude-haiku-5-5",
    content,
    stop_reason,
    stop_sequence: null,
    usage: { input_tokens: 1000, output_tokens: 200, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, server_tool_use: { web_search_requests: searches, web_fetch_requests: 0 } },
  }) as unknown as Message;
const listing = (over: Partial<ReportedListing>): ReportedListing => ({
  source_url: "",
  price: 0,
  currency: "KZT",
  deal: "sale",
  size_m2: null,
  land_ares: null,
  rooms: null,
  rooms_text: null,
  year: null,
  mileage_km: null,
  district: null,
  new_building: null,
  ...over,
});

// The flat of docs/plan-assets-roadmap.md §3: listing pages from a search on 2026-11-02.
const KRISHA = "https://krisha.kz/prodazha/kvartiry/almaty-bostandykskij/?das[live.rooms]=2";
const KRISHA_AGENCY = "https://krisha.kz/prodazha/kvartiry/almaty-bostandykskij/?das[who]=2&das[live.rooms]=2";
const KORTER_ENCODED =
  "https://korter.kz/%D0%BF%D1%80%D0%BE%D0%B4%D0%B0%D0%B6%D0%B0-%D0%BA%D0%B2%D0%B0%D1%80%D1%82%D0%B8%D1%80-%D0%B0%D0%BB%D0%BC%D0%B0%D1%82%D1%8B";
const KORTER_AS_WRITTEN = "https://korter.kz/продажа-квартир-алматы";
const NEDV_PRO = "https://nedvizhimostpro.kz/page/373";
const NEDVIZHKA = "https://nedvizhka.kz/posts/kvartiry-prodazha/almaty/bostandykskiy-rayon";
const OLX = "https://m.olx.kz/nedvizhimost/prodazha-kvartiry/alma-ata/";
const ETAGI = "https://almaty.etagi.com/realty/dvuhkomnatnye-kvartiry/r-bostandykskijj/";
const DOM = "https://dom.kz/prodazha/kvartiry/almaty-bostandykskij/dvuhkomnatnye?pageNum=8";

const flat: AssetDescription = {
  kind: "apartment",
  country: "KZ",
  city: "Алматы",
  district: "Бостандыкский",
  area_m2: 65,
  rooms: 2,
  year_built: 2015,
  building: "monolith",
};

const flatResults = searchResults(searched("s1", "2-комнатная квартира Бостандыкский район продажа", [KRISHA, KRISHA_AGENCY, KORTER_ENCODED, NEDV_PRO, NEDVIZHKA, OLX, ETAGI, DOM]));

const flatReport: Report = {
  listings: [
    listing({ source_url: KRISHA, price: 48_000_000, size_m2: 60.9, rooms: 2 }),
    listing({ source_url: KRISHA, price: 35_000_000, size_m2: 45, rooms: 2 }),
    listing({ source_url: KORTER_AS_WRITTEN, price: 28_000_000, size_m2: 40 }),
    listing({ source_url: KORTER_AS_WRITTEN, price: 45_500_000, size_m2: 58.1 }),
    listing({ source_url: NEDV_PRO, price: 55_000_000, size_m2: 72 }),
    listing({ source_url: NEDV_PRO, price: 34_000_000, size_m2: 52 }),
    listing({ source_url: NEDV_PRO, price: 45_000_000 }),
    listing({ source_url: NEDV_PRO, price: 45_500_000, size_m2: 58.1 }), // the Korter listing again
    listing({ source_url: NEDVIZHKA, price: 57_000_000, size_m2: 68, rooms: 2, new_building: true }),
    listing({ source_url: KRISHA_AGENCY, price: 44_000_000, size_m2: 62, rooms: 2 }),
    listing({ source_url: KRISHA_AGENCY, price: 80_000_000, rooms: 2 }),
    listing({ source_url: OLX, price: 74_000_000 }),
    listing({ source_url: OLX, price: 65_000_000 }),
    listing({ source_url: OLX, price: 40_000_000 }),
    listing({ source_url: DOM, price: 69_500, deal: "rent" }),
    listing({ source_url: "https://krisha.kz/a/show/999999999", price: 50_000_000, size_m2: 65, rooms: 2 }), // not in the results
  ],
  site_averages: [{ source_url: ETAGI, value: 56_865_345, currency: "KZT", per: "total" }],
};

// The car: Toyota Camry 70, 2019, from the same day's search.
const camry: AssetDescription = { kind: "vehicle", country: "KZ", city: "Алматы", make: "Toyota", model: "Camry", generation: "XV70", year: 2019, engine_l: 2.5, mileage_km: 110_000 };
const K = (path: string) => `https://kolesa.kz/${path}`;
const camryResults = searchResults(searched("s1", "Toyota Camry 70 2019 купить", [K("cars/toyota/camry/almaty/"), K("cars/toyota/camry/?page=525"), K("a/show/232401950"), K("cars/toyota/camry/astana/"), "https://autobazar.kz/camry"]));
const camryReport: Report = {
  listings: [
    listing({ source_url: K("cars/toyota/camry/almaty/"), price: 13_300_000, year: 2019, mileage_km: 156_000 }),
    listing({ source_url: K("cars/toyota/camry/?page=525"), price: 13_400_000, year: 2019, mileage_km: 150_000 }),
    listing({ source_url: K("cars/toyota/camry/almaty/"), price: 12_500_000, year: 2019 }),
    listing({ source_url: "https://autobazar.kz/camry", price: 13_900_000, year: 2019, mileage_km: 102_000 }),
    listing({ source_url: K("a/show/232401950"), price: 12_500_000, year: 2019, mileage_km: 111_000 }),
    listing({ source_url: K("cars/toyota/camry/almaty/"), price: 13_600_000, year: 2019 }),
    listing({ source_url: K("cars/toyota/camry/astana/"), price: 13_100_000, year: 2023, mileage_km: 90_000 }),
  ],
  site_averages: [],
};

describe("parseValuationRequest", () => {
  const parse = (asset: unknown, extra: Record<string, unknown> = {}) => parseValuationRequest(JSON.stringify({ protocol: 1, asset, ...extra }));
  const reason = (fn: () => unknown) => {
    try {
      fn();
    } catch (error) {
      return (error as { code?: string }).code;
    }
    return "accepted";
  };

  it("takes a flat with its place and characteristics, and a car", () => {
    expect(parse(flat, { user: "$RCAnonymousID:abc" }).asset).toEqual(flat);
    expect(parse(camry).asset.mileage_km).toBe(110_000);
  });

  it("needs what the value is computed from", () => {
    expect(reason(() => parse({ kind: "apartment", country: "KZ", city: "Алматы" }))).toBe("area_m2");
    expect(reason(() => parse({ kind: "land", country: "KZ", city: "Каскелен" }))).toBe("land_ares");
    expect(reason(() => parse({ kind: "vehicle", country: "KZ", make: "Toyota", model: "Camry" }))).toBe("year");
    expect(reason(() => parse({ kind: "other", country: "KZ" }))).toBe("description");
  });

  it("refuses fields it does not know or that do not fit the kind", () => {
    expect(reason(() => parse({ ...flat, name: "Квартира на Абая" }))).toBe("field");
    expect(reason(() => parse({ ...flat, mileage_km: 1 }))).toBe("mileage_km_for_kind");
    expect(reason(() => parse(flat, { messages: [] }))).toBe("field");
  });

  it("refuses what looks like a phone number, an IIN or a VIN", () => {
    expect(reason(() => parse({ ...flat, district: "+7 701 123 45 67" }))).toBe("district");
    expect(reason(() => parse({ ...camry, generation: "JTNB11HK103456789" }))).toBe("generation");
    // A complex with a number in its name is fine.
    expect(parse({ ...flat, complex: "Nurly Tau 2" }).asset.complex).toBe("Nurly Tau 2");
  });

  it("checks the envelope", () => {
    expect(reason(() => parseValuationRequest("{"))).toBe("json");
    expect(reason(() => parse(flat, { protocol: 2 }))).toBe("protocol");
    expect(reason(() => parse({ ...flat, country: "kz" }))).toBe("country");
    expect(reason(() => parse({ ...flat, kind: "yacht" }))).toBe("kind");
    expect(reason(() => parse({ ...flat, district: "x".repeat(81) }))).toBe("district");
    expect(reason(() => parseValuationRequest(JSON.stringify({ protocol: 1, asset: { ...flat, complex: "y".repeat(80) }, pad: "z".repeat(9000) })))).toBe("size");
  });
});

describe("buildValuationParams", () => {
  it("gives the dynamic-filtering search to the models that have it, and the place where the search takes it", () => {
    const haiku = buildValuationParams(valuationConfig(readConfig({})), flat, now);
    expect(haiku.model).toBe("claude-haiku-5-5");
    // Web search refuses KZ as a user_location (a 400): the place stays in the asset's text.
    expect(haiku.tools?.[0]).toMatchObject({ type: "web_search_20250305", max_uses: 3 });
    expect(haiku.tools?.[0]).not.toHaveProperty("user_location");
    const madrid = buildValuationParams(valuationConfig(readConfig({})), { kind: "apartment", country: "ES", city: "Madrid", area_m2: 80 }, now);
    expect(madrid.tools?.[0]).toMatchObject({ user_location: { type: "approximate", country: "ES", city: "Madrid" } });
    const sonnet = buildValuationParams(valuationConfig(readConfig({ VALUATION_MODEL: "claude-sonnet-5-5", VALUATION_MAX_SEARCHES: "4" })), flat, now);
    expect(sonnet.tools?.[0]).toMatchObject({ type: "web_search_20260209", max_uses: 4 });
  });

  it("only searches and reports: no page fetches, a strict report, no forced tool", () => {
    const params = buildValuationParams(valuationConfig(readConfig({})), flat, now);
    expect(params.tools?.map(toolName)).toEqual(["web_search", REPORT_LISTINGS]);
    expect(params.tools?.some((t) => "type" in t && String(t.type).startsWith("web_fetch"))).toBe(false);
    expect(REPORT_LISTINGS_TOOL.strict).toBe(true);
    expect(params.tool_choice).toEqual({ type: "auto" });
  });

  it("keeps per-request values out of the system prompt and sends no name", () => {
    expect(VALUATION_SYSTEM_PROMPT).not.toMatch(/\d{4}-\d{2}-\d{2}/);
    expect(VALUATION_SYSTEM_PROMPT).not.toContain("—");
    const params = buildValuationParams(valuationConfig(readConfig({})), flat, now);
    const text = JSON.stringify(params.messages);
    expect(text).toContain("2026-11-02");
    expect(text).toContain("Бостандыкский");
  });

  it("stays under the API's limit of 16 nullable parameters in strict tools", () => {
    const count = (schema: unknown): number => {
      if (Array.isArray(schema)) return schema.reduce((n, s) => n + count(s), 0);
      if (!schema || typeof schema !== "object") return 0;
      const node = schema as Record<string, unknown>;
      return (Array.isArray(node.anyOf) ? 1 : 0) + Object.values(node).reduce((n: number, v) => n + count(v), 0);
    };
    expect(count(REPORT_LISTINGS_TOOL.input_schema)).toBeLessThanOrEqual(16);
  });
});

describe("normalizeUrl", () => {
  it("compares two spellings of one page", () => {
    expect(normalizeUrl(KORTER_ENCODED)).toBe(normalizeUrl(KORTER_AS_WRITTEN));
    expect(normalizeUrl("https://www.kolesa.kz/cars/")).toBe(normalizeUrl("https://kolesa.kz/cars#top"));
    expect(normalizeUrl("https://m.krisha.kz/a/show/1")).toBe(normalizeUrl("https://krisha.kz/a/show/1"));
    expect(normalizeUrl("ftp://krisha.kz/")).toBeUndefined();
    expect(normalizeUrl("not a url")).toBeUndefined();
  });
});

describe("computeValuation", () => {
  it("prices the flat by the square metre of six comparables", () => {
    const value = computeValuation(flat, flatReport, flatResults, now);
    expect(value).toMatchObject({
      status: "ok",
      currency: "KZT",
      basis: "per_unit",
      value: 50_300_000,
      low: 47_000_000,
      high: 51_100_000,
      per_unit: { unit: "m2", median: 774_000, low: 723_000, high: 787_000 },
      count: 6,
      accuracy: "medium",
    });
    expect(value.excluded).toEqual({ unverified_url: 1, rent: 1, duplicate: 1, size: 7 });
    // Every link shown is one of the search results, with its title.
    expect(value.listings.every((l) => flatResults.has(normalizeUrl(l.url)!))).toBe(true);
    expect(value.listings[0]).toMatchObject({ price: 34_000_000, site: "nedvizhimostpro.kz" });
    // A site's own average is shown beside, never counted.
    expect(value.site_averages).toEqual([{ title: "Listings", url: ETAGI, value: 56_865_345, currency: "KZT", per: "total" }]);
  });

  it("prices the car among the same years, by mileage when three are close", () => {
    const close = computeValuation(camry, camryReport, camryResults, now);
    expect(close).toMatchObject({ status: "ok", basis: "price", value: 13_400_000, count: 3, accuracy: "low" });
    expect(close.excluded).toEqual({ year: 1, mileage: 3 });

    const { mileage_km: _, ...anyMileage } = camry;
    const all = computeValuation(anyMileage, camryReport, camryResults, now);
    expect(all).toMatchObject({ status: "ok", value: 13_400_000, low: 12_700_000, high: 13_600_000, count: 6, accuracy: "medium" });
  });

  it("takes the currency most listings are in", () => {
    const urls = ["https://a.kz/1", "https://a.kz/2"];
    const results = searchResults(searched("s", "q", urls));
    const report: Report = {
      listings: [10, 11, 12, 13].map((m) => listing({ source_url: urls[0]!, price: m * 1_000_000, size_m2: 65 })).concat(listing({ source_url: urls[1]!, price: 25_000, currency: "usd", size_m2: 65 })),
      site_averages: [],
    };
    const value = computeValuation(flat, report, results, now);
    expect(value).toMatchObject({ currency: "KZT", count: 4 });
    expect(value.excluded).toEqual({ currency: 1 });
  });

  it("drops an outlier once there are enough listings to tell", () => {
    const url = "https://a.kz/list";
    const results = searchResults(searched("s", "q", [url]));
    const perM2 = [700, 710, 720, 730, 740, 750, 760, 770, 1_400];
    const report: Report = { listings: perM2.map((k, i) => listing({ source_url: url, price: k * 1000 * (60 + i), size_m2: 60 + i })), site_averages: [] };
    const value = computeValuation({ ...flat, area_m2: 64 }, report, results, now);
    expect(value.excluded).toEqual({ outlier: 1 });
    expect(value).toMatchObject({ count: 8, accuracy: "high" });
  });

  it("drops prices misread by a power of ten even when they are many", () => {
    // As in the eval's Istanbul run: real asking prices of 13-26 million and a cluster read as
    // 0.4-2.4 million for the same 100 m².
    const url = "https://www.hepsiemlak.com/kadikoy-satilik/daire-2-1";
    const results = searchResults(searched("s", "Kadıköy satılık daire 2+1", [url]));
    const real = [25_950_000, 22_500_000, 15_950_000, 12_650_000, 13_200_000, 21_500_000, 17_300_000, 14_500_000, 14_450_000];
    const misread = [515_000, 920_000, 600_000, 475_000, 430_000, 950_000, 560_000, 2_350_000];
    const report: Report = { listings: [...real, ...misread].map((price, i) => listing({ source_url: url, price, currency: "TRY", size_m2: 100 + (i % 3), rooms: 2 })), site_averages: [] };
    const kadikoy: AssetDescription = { kind: "apartment", country: "TR", city: "İstanbul", district: "Kadıköy", area_m2: 100, rooms: 2 };
    const value = computeValuation(kadikoy, report, results, now);
    expect(value.excluded).toEqual({ outside_cluster: 8 });
    expect(value).toMatchObject({ status: "ok", currency: "TRY", count: 9 });
    expect(value.value! / 15_950_000).toBeGreaterThan(0.95);
    expect(value.value! / 15_950_000).toBeLessThan(1.05);
  });

  it("keeps the dearer of two groups as large as each other", () => {
    // As in run 120's Istanbul search: eight real prices and eight read ten times too low.
    expect(densestGroup([126_500, 159_500, 203_500, 225_000, 253_000, 259_500, 267_700, 132_400, 5_150, 9_200, 4_780, 6_220, 10_900, 9_500, 6_670, 5_590])).toEqual([126_500, 267_700]);
    expect(densestGroup([100, 120, 130])).toEqual([100, 130]);
    expect(densestGroup([100])).toEqual([100, 100]);
    // Pages, not listings: eight stale prices of two results pages lose to six real ones of four.
    const stale = [4_780, 5_150, 5_590, 6_220, 6_670, 9_200, 9_500, 10_900];
    const real = [126_500, 159_500, 203_500, 225_000, 253_000, 259_500];
    const pages = [...stale.map((_, i) => (i % 2 ? "sahibinden-a" : "sahibinden-b")), "p1", "p2", "p3", "p4", "p1", "p2"];
    expect(densestGroup([...stale, ...real], pages)).toEqual([126_500, 259_500]);
    expect(densestGroup([...stale, ...real])).toEqual([4_780, 10_900]);
  });

  it("counts Turkey's 2+1 as two rooms whatever the model wrote, and ignores rooms that would leave nothing", () => {
    // As in eval run 122: Haiku wrote 3 for every 2+1, and the rooms filter left none of 18.
    const url = "https://www.hepsiemlak.com/kadikoy-satilik/daire-2-1";
    const results = searchResults(searched("s", "Kadıköy satılık daire 2+1", [url]));
    const kadikoy: AssetDescription = { kind: "apartment", country: "TR", city: "İstanbul", district: "Kadıköy", area_m2: 100, rooms: 2 };
    const prices = [25_950_000, 22_500_000, 15_950_000, 12_650_000, 17_300_000];
    const asWritten = computeValuation(kadikoy, { listings: prices.map((price) => listing({ source_url: url, price, currency: "TRY", size_m2: 100, rooms: 3, rooms_text: "2+1" })), site_averages: [] }, results, now);
    expect(asWritten).toMatchObject({ status: "ok", count: 5 });
    expect(asWritten.excluded).toEqual({});
    const unwritten = computeValuation(kadikoy, { listings: prices.map((price) => listing({ source_url: url, price, currency: "TRY", size_m2: 100, rooms: 3 })), site_averages: [] }, results, now);
    expect(unwritten).toMatchObject({ status: "ok", count: 5 });
    // A wider match: at most medium.
    expect(unwritten.accuracy).not.toBe("high");
  });

  it("prices by the many same-room listings when only a few give a size", () => {
    // As in the eval's London run: five sizes among twenty two-bedroom listings, all cheap ones.
    const url = "https://www.rightmove.co.uk/property-for-sale/Lewisham/2-bed-flats.htm";
    const results = searchResults(searched("s", "2 bedroom flat for sale Lewisham", [url]));
    const sized = [275_000, 350_000, 350_000, 275_000, 300_000].map((price, i) => listing({ source_url: url, price, currency: "GBP", rooms: 2, size_m2: 59 + i * 2 }));
    const unsized = [700_000, 675_000, 625_000, 500_000, 600_000, 430_000, 425_000, 300_000, 240_000, 365_000, 475_000, 355_000, 535_000, 550_000, 375_000].map((price) =>
      listing({ source_url: url, price, currency: "GBP", rooms: 2 }),
    );
    const lewisham: AssetDescription = { kind: "apartment", country: "GB", city: "London", district: "Lewisham", area_m2: 65, rooms: 2 };
    const value = computeValuation(lewisham, { listings: [...sized, ...unsized], site_averages: [] }, results, now);
    expect(value).toMatchObject({ status: "ok", basis: "price", count: 20, value: 400_000 });
  });

  it("prices by the listing price among the same rooms when sizes are missing", () => {
    const url = "https://www.rightmove.co.uk/property-for-sale/Lewisham.html";
    const results = searchResults(searched("s", "2 bed flat for sale Lewisham", [url]));
    const report: Report = {
      listings: [400_000, 425_000, 390_000, 450_000].map((price) => listing({ source_url: url, price, currency: "GBP", rooms: 2 })).concat(listing({ source_url: url, price: 600_000, currency: "GBP", rooms: 3 })),
      site_averages: [],
    };
    const lewisham: AssetDescription = { kind: "apartment", country: "GB", city: "London", district: "Lewisham", area_m2: 65, rooms: 2 };
    const value = computeValuation(lewisham, report, results, now);
    expect(value).toMatchObject({ status: "ok", currency: "GBP", basis: "price", value: 413_000, count: 4, accuracy: "low", per_unit: null });
    expect(value.excluded).toEqual({ rooms: 1 });
  });

  it("says there are too few listings rather than guess", () => {
    const url = "https://a.kz/list";
    const report: Report = { listings: [listing({ source_url: url, price: 40_000_000, size_m2: 60, rooms: 2 }), listing({ source_url: url, price: 42_000_000, size_m2: 62, rooms: 2 })], site_averages: [] };
    const value = computeValuation(flat, report, searchResults(searched("s", "q", [url])), now);
    expect(value).toMatchObject({ status: "insufficient", reason: "few_listings", value: null, count: 2, currency: "KZT" });
    expect(computeValuation(flat, undefined, new Map(), now)).toMatchObject({ status: "insufficient", reason: "no_report" });
  });
});

describe("searchListings", () => {
  const config = valuationConfig(readConfig({}));

  it("goes on after a paused turn and collects the results of every round", async () => {
    const sent: Anthropic.Beta.Messages.MessageCreateParamsNonStreaming[] = [];
    const replies = [message(searched("s1", "first", [KRISHA]), "pause_turn"), message([...searched("s2", "second", [NEDV_PRO]), reported(flatReport)], "tool_use")];
    const outcome = await searchListings(async (params) => (sent.push(params), replies.shift()!), config, flat, now);
    expect(outcome.calls).toBe(2);
    expect(outcome.queries).toEqual(["first", "second"]);
    expect([...outcome.results.keys()]).toEqual([normalizeUrl(KRISHA), normalizeUrl(NEDV_PRO)]);
    expect(outcome.usage.searches).toBe(2);
    expect(outcome.report?.listings).toHaveLength(flatReport.listings.length);
    // The second call carries the paused content and only the searches left.
    expect(sent[1]!.messages).toHaveLength(2);
    expect(sent[1]!.tools?.[0]).toMatchObject({ name: "web_search", max_uses: 2 });
  });

  it("asks once for the report when the model stopped without it", async () => {
    const sent: Anthropic.Beta.Messages.MessageCreateParamsNonStreaming[] = [];
    const text = { type: "text", text: "Here is what I found." } as unknown as Block;
    const replies = [message([...searched("s1", "q", [KRISHA]), text], "end_turn", 3), message([reported({ listings: [], site_averages: [] })], "tool_use", 0)];
    const outcome = await searchListings(async (params) => (sent.push(params), replies.shift()!), config, flat, now);
    expect(outcome.report).toEqual({ listings: [], site_averages: [] });
    const last = sent[1]!.messages.at(-1)!;
    expect(last.role).toBe("user");
    expect(JSON.stringify(last.content)).toContain(REPORT_LISTINGS);
    // The searches were spent: the tool stays (its calls are in the history) with one left.
    expect(sent[1]!.tools?.[0]).toMatchObject({ name: "web_search", max_uses: 1 });
  });

  it("asks again without a location the search refuses", async () => {
    const sent: Anthropic.Beta.Messages.MessageCreateParamsNonStreaming[] = [];
    const istanbul: AssetDescription = { kind: "apartment", country: "TR", city: "İstanbul", area_m2: 100 };
    let first = true;
    const outcome = await searchListings(
      async (params) => {
        sent.push(params);
        if (first) {
          first = false;
          throw Object.assign(new Error("400 tools.0.web_search_20250305: Country code TR is not supported."), { status: 400 });
        }
        return message([reported({ listings: [], site_averages: [] })], "tool_use", 1);
      },
      config,
      istanbul,
      now,
    );
    expect(outcome.report).toEqual({ listings: [], site_averages: [] });
    expect(sent[0]!.tools?.[0]).toHaveProperty("user_location");
    expect(sent[1]!.tools?.[0]).not.toHaveProperty("user_location");
    // Another error is not retried.
    await expect(searchListings(async () => Promise.reject(Object.assign(new Error("400 max_tokens"), { status: 400 })), config, istanbul, now)).rejects.toThrow("max_tokens");
  });

  it("takes no report from a turn cut off by max_tokens", async () => {
    const cut = message([...searched("s1", "q", [KRISHA]), reported({ listings: [], site_averages: [] })], "max_tokens");
    const outcome = await searchListings(async () => cut, config, flat, now);
    expect(outcome).toMatchObject({ truncated: true, calls: 1, report: undefined });
    expect(buildValuationParams(config, flat, now).max_tokens).toBe(16000);
  });

  it("stops on a refusal", async () => {
    const outcome = await searchListings(async () => message([], "refusal", 0), config, flat, now);
    expect(outcome).toMatchObject({ refused: true, calls: 1, report: undefined });
  });
});

describe("valuate", () => {
  const listings = (n: number) =>
    reported({ listings: Array.from({ length: n }, (_, i) => listing({ source_url: KRISHA, price: 48_000_000 + i * 1_000_000, size_m2: 62 + i, rooms: 2 })), site_averages: [] });

  it("asks the fallback model again when the first finds too few listings", async () => {
    const config = valuationConfig(readConfig({ VALUATION_FALLBACK_MODEL: "claude-sonnet-5-5" }));
    const models: string[] = [];
    const valuation = await valuate(
      async (params) => {
        models.push(params.model);
        return params.model === "claude-haiku-5-5"
          ? message([...searched("s1", "q", [KRISHA]), reported({ listings: [], site_averages: [] })], "tool_use")
          : message([...searched("s2", "q", [KRISHA]), listings(5)], "tool_use");
      },
      config,
      flat,
      now,
    );
    expect(models).toEqual(["claude-haiku-5-5", "claude-sonnet-5-5"]);
    expect(valuation).toMatchObject({ model: "claude-sonnet-5-5", usedFallback: true, result: { status: "ok", count: 5 } });
    expect(valuation.searches.map((s) => s.model)).toEqual(["claude-haiku-5-5", "claude-sonnet-5-5"]);
  });

  it("keeps the first model's value when it found enough, and without a fallback", async () => {
    const answer = async () => message([...searched("s1", "q", [KRISHA]), listings(5)], "tool_use");
    const withFallback = await valuate(answer, valuationConfig(readConfig({ VALUATION_FALLBACK_MODEL: "claude-sonnet-5-5" })), flat, now);
    expect(withFallback).toMatchObject({ model: "claude-haiku-5-5", usedFallback: false });
    const empty = async () => message([reported({ listings: [], site_averages: [] })], "tool_use");
    const alone = await valuate(empty, valuationConfig(readConfig({})), flat, now);
    expect(alone).toMatchObject({ usedFallback: false, result: { status: "insufficient" } });
    expect(alone.searches).toHaveLength(1);
  });
});

describe("POST /v1/valuation", () => {
  const ctx = { waitUntil() {}, passThroughOnException() {} } as never;
  const env = (overrides: Record<string, string>, kv = new MemoryKV()) => ({ QUOTA: kv, ANTHROPIC_API_KEY: "test", REVENUECAT_SECRET_KEY: "test", ...overrides }) as never;
  const post = (headers: Record<string, string>, body: string) => new Request("https://assistant.example/v1/valuation", { method: "POST", headers, body });
  const body = JSON.stringify({ protocol: 1, asset: flat });

  it("is off until VALUATION_ENABLED", async () => {
    expect((await worker.fetch(post({ "x-tenra-user": "u" }, body), env({}), ctx)).status).toBe(503);
    const health = await worker.fetch(new Request("https://assistant.example/v1/health"), env({ VALUATION_ENABLED: "true" }), ctx);
    expect(await health.json()).toMatchObject({ valuation: expect.any(String) });
  });

  it("refuses a malformed asset before anything else", async () => {
    const response = await worker.fetch(post({ "x-tenra-user": "u" }, JSON.stringify({ protocol: 1, asset: { kind: "apartment", country: "KZ" } })), env({ VALUATION_ENABLED: "true" }), ctx);
    expect(response.status).toBe(400);
    expect(await response.json()).toEqual({ error: "invalid", reason: "city" });
  });

  it("needs the app's signature, then counts valuations on their own", async () => {
    const kv = new MemoryKV();
    await kv.put("tier:u", "free");
    await kv.put(`attest-key:${fixture.keyId}`, await storedKey());
    const config = { VALUATION_ENABLED: "true", APP_ID: fixture.appId, FREE_MONTHLY_VALUATIONS: "0" };

    const unsigned = await worker.fetch(post({ "x-tenra-user": "u" }, body), env(config, kv), ctx);
    expect(await unsigned.json()).toEqual({ error: "attest", reason: "missing" });

    const signed = await worker.fetch(
      post({ "x-tenra-user": "u", "x-tenra-key": fixture.keyId, "x-tenra-assertion": await assertion(new TextEncoder().encode(body), 1) }, body),
      env(config, kv),
      ctx,
    );
    expect(signed.status).toBe(429);
    expect(await signed.json()).toMatchObject({ error: "quota", tier: "free", limit: 0 });
  });
});

describe("consumeValuation", () => {
  it("has its own monthly count and weighs on the global daily stop", async () => {
    const kv = new MemoryKV();
    const config = readConfig({ PRO_MONTHLY_VALUATIONS: "5", GLOBAL_DAILY_CALLS: "60", VALUATION_CALL_WEIGHT: "25" });
    expect(await consumeValuation(kv, "p", "pro", config, now)).toMatchObject({ allowed: true, used: 1, limit: 5 });
    expect(kv.store.get("valuations:p:2026-11")).toBe("1");
    expect(kv.store.get("calls:all:2026-11-02")).toBe("25");
    expect((await consumeValuation(kv, "p", "pro", config, now)).allowed).toBe(true);
    // A third would take the day to 75 of 60.
    expect(await consumeValuation(kv, "p", "pro", config, now)).toMatchObject({ allowed: false, reason: "global" });
    expect(readConfig({})).toMatchObject({ valuationEnabled: false, freeMonthlyValuations: 0, proMonthlyValuations: 10, valuationMaxSearches: 3, valuationFallbackModel: "" });
  });
});

describe("the valuation eval", () => {
  it("has cases the endpoint accepts, each with a dated reference", async () => {
    const { VALUATION_CASES } = await import("../eval/valuation-cases");
    expect(VALUATION_CASES.length).toBeGreaterThanOrEqual(20);
    expect(new Set(VALUATION_CASES.map((c) => c.id)).size).toBe(VALUATION_CASES.length);
    for (const c of VALUATION_CASES) {
      expect(parseValuationRequest(JSON.stringify({ protocol: 1, asset: c.asset })).asset).toEqual(c.asset);
      if (c.expect.status === "ok") expect(c.expect.asOf).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    }
    // More than one country, and a case whose honest answer is "too few".
    expect(new Set(VALUATION_CASES.map((c) => c.asset.country)).size).toBeGreaterThanOrEqual(5);
    expect(VALUATION_CASES.some((c) => c.expect.status === "insufficient")).toBe(true);
  });

  it("grades a value by its reference's tolerance and currency", async () => {
    const { grade } = await import("../eval/valuation");
    const { VALUATION_CASES } = await import("../eval/valuation-cases");
    const almaty = VALUATION_CASES.find((c) => c.id === "kz-almaty-flat-2r")!;
    const value = computeValuation(flat, flatReport, flatResults, now);
    expect(grade(almaty, value)).toMatchObject({ pass: true });
    expect(grade(almaty, { ...value, value: 60_000_000 }).pass).toBe(false);
    expect(grade(almaty, { ...value, currency: "USD" }).pass).toBe(false);
    const handmade = VALUATION_CASES.find((c) => c.expect.status === "insufficient")!;
    expect(grade(handmade, { ...value, accuracy: "low" }).pass).toBe(true);
    expect(grade(handmade, value).pass).toBe(false);
  });
});
