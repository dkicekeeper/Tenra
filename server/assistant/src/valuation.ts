import type Anthropic from "@anthropic-ai/sdk";
import type { Config } from "./config";
import { isValidUserId, PROTOCOL_VERSION, ValidationError } from "./validate";

// POST /v1/valuation: what an asset is worth by listings of comparable ones, in any country
// (docs/plan-assets-roadmap.md §3, docs/domains/assistant.md §8). The model only searches and
// copies listings out of the search results into report_listings; this file checks every
// listing against those results (a URL that was not among them is dropped) and does all the
// arithmetic: comparables by kind, the market currency, outliers, median and quartiles. The
// request carries the asset's kind, place and characteristics, never its name or an address,
// and nothing of it is logged.

export const VALUATION_PROMPT_VERSION = "2026-11-02.3";
export const REPORT_LISTINGS = "report_listings";

type Params = Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;
type Message = Anthropic.Beta.BetaMessage;
type ContentBlock = Anthropic.Beta.BetaContentBlock;
type MessageParam = Anthropic.Beta.BetaMessageParam;

// MARK: - The request

export const ASSET_KINDS = ["apartment", "house", "land", "commercial", "vehicle", "other"] as const;
export type AssetKind = (typeof ASSET_KINDS)[number];

const BUILDINGS = ["panel", "brick", "monolith", "block", "wood", "other"] as const;
const CONDITIONS = ["rough", "needs_repair", "standard", "good", "excellent"] as const;
const LAND_USES = ["residential", "garden", "farm", "commercial", "other"] as const;
const UTILITIES = ["gas", "water", "sewer", "electricity"] as const;
const COMMERCIAL_TYPES = ["office", "retail", "warehouse", "other"] as const;
const FUELS = ["petrol", "diesel", "hybrid", "electric", "gas", "other"] as const;
const TRANSMISSIONS = ["automatic", "manual"] as const;
const DRIVES = ["fwd", "rwd", "awd"] as const;
const STEERINGS = ["left", "right"] as const;

/** What the phone sends about one asset. Sizes are in square metres and ares (a sotka is an are). */
export interface AssetDescription {
  kind: AssetKind;
  /** ISO 3166-1 alpha-2. */
  country: string;
  city?: string;
  region?: string;
  district?: string;
  /** A residential complex or a building's name. */
  complex?: string;
  area_m2?: number;
  /** As the country's listings count them: rooms in Kazakhstan, bedrooms in the UK and the US, the first number of "2+1" in Turkey. */
  rooms?: number;
  year_built?: number;
  new_building?: boolean;
  building?: (typeof BUILDINGS)[number];
  floor?: number;
  floors?: number;
  condition?: (typeof CONDITIONS)[number];
  land_ares?: number;
  land_use?: (typeof LAND_USES)[number];
  utilities?: (typeof UTILITIES)[number][];
  commercial_type?: (typeof COMMERCIAL_TYPES)[number];
  make?: string;
  model?: string;
  generation?: string;
  year?: number;
  engine_l?: number;
  fuel?: (typeof FUELS)[number];
  transmission?: (typeof TRANSMISSIONS)[number];
  drive?: (typeof DRIVES)[number];
  mileage_km?: number;
  /** Kazakhstan: registered in the country (a car that is not sells for less). */
  customs_cleared?: boolean;
  steering?: (typeof STEERINGS)[number];
  /** What the thing is, for `other`: "Rolex Submariner 116610LN". */
  description?: string;
}

export interface ValuationRequest {
  protocol: number;
  user?: string;
  asset: AssetDescription;
}

type FieldRule =
  | { type: "text"; max: number }
  | { type: "int"; min: number; max: number }
  | { type: "number"; min: number; max: number }
  | { type: "bool" }
  | { type: "enum"; values: readonly string[] }
  | { type: "set"; values: readonly string[] };

const thisYear = () => new Date().getUTCFullYear();

const FIELDS: Record<Exclude<keyof AssetDescription, "kind" | "country">, FieldRule> = {
  city: { type: "text", max: 80 },
  region: { type: "text", max: 80 },
  district: { type: "text", max: 80 },
  complex: { type: "text", max: 80 },
  area_m2: { type: "number", min: 5, max: 100_000 },
  rooms: { type: "int", min: 0, max: 30 },
  year_built: { type: "int", min: 1700, max: 2100 },
  new_building: { type: "bool" },
  building: { type: "enum", values: BUILDINGS },
  floor: { type: "int", min: -5, max: 200 },
  floors: { type: "int", min: 1, max: 200 },
  condition: { type: "enum", values: CONDITIONS },
  land_ares: { type: "number", min: 0.1, max: 1_000_000 },
  land_use: { type: "enum", values: LAND_USES },
  utilities: { type: "set", values: UTILITIES },
  commercial_type: { type: "enum", values: COMMERCIAL_TYPES },
  make: { type: "text", max: 40 },
  model: { type: "text", max: 40 },
  generation: { type: "text", max: 40 },
  year: { type: "int", min: 1900, max: 2100 },
  engine_l: { type: "number", min: 0.1, max: 20 },
  fuel: { type: "enum", values: FUELS },
  transmission: { type: "enum", values: TRANSMISSIONS },
  drive: { type: "enum", values: DRIVES },
  mileage_km: { type: "number", min: 0, max: 3_000_000 },
  customs_cleared: { type: "bool" },
  steering: { type: "enum", values: STEERINGS },
  description: { type: "text", max: 160 },
};

const PLACE = ["city", "region", "district", "complex"] as const;
const BUILDING_FIELDS = ["area_m2", "rooms", "year_built", "new_building", "building", "floor", "floors", "condition"] as const;

/** The fields each kind may carry, and the ones it must. */
const KIND_FIELDS: Record<AssetKind, { allowed: readonly string[]; required: readonly string[][] }> = {
  apartment: { allowed: [...PLACE, ...BUILDING_FIELDS], required: [["city"], ["area_m2"]] },
  house: { allowed: [...PLACE, ...BUILDING_FIELDS, "land_ares", "utilities"], required: [["city", "region"], ["area_m2"]] },
  commercial: { allowed: [...PLACE, ...BUILDING_FIELDS, "commercial_type"], required: [["city"], ["area_m2"]] },
  land: { allowed: [...PLACE, "land_ares", "land_use", "utilities"], required: [["city", "region"], ["land_ares"]] },
  vehicle: {
    allowed: ["city", "region", "make", "model", "generation", "year", "engine_l", "fuel", "transmission", "drive", "mileage_km", "customs_cleared", "steering", "condition"],
    required: [["make"], ["model"], ["year"]],
  },
  other: { allowed: ["city", "region", "description", "year", "condition"], required: [["description"]] },
};

export const VALUATION_LIMITS = { bodyBytes: 8 * 1024 };

// A phone number, an IIN, a VIN, a plate with its digits: the request never needs them.
const TOO_MANY_DIGITS = /(?:\d\D?){7,}/;
const CONTROL = /[\u0000-\u001f\u007f]/;

function checkField(name: string, rule: FieldRule, value: unknown): unknown {
  switch (rule.type) {
    case "text": {
      if (typeof value !== "string") throw new ValidationError(name);
      const text = value.trim();
      if (!text || text.length > rule.max || CONTROL.test(text) || TOO_MANY_DIGITS.test(text)) throw new ValidationError(name);
      return text;
    }
    case "int":
      if (typeof value !== "number" || !Number.isInteger(value) || value < rule.min || value > rule.max) throw new ValidationError(name);
      return value;
    case "number":
      if (typeof value !== "number" || !Number.isFinite(value) || value < rule.min || value > rule.max) throw new ValidationError(name);
      return value;
    case "bool":
      if (typeof value !== "boolean") throw new ValidationError(name);
      return value;
    case "enum":
      if (typeof value !== "string" || !rule.values.includes(value)) throw new ValidationError(name);
      return value;
    case "set":
      if (!Array.isArray(value) || value.length > rule.values.length || value.some((v) => typeof v !== "string" || !rule.values.includes(v))) {
        throw new ValidationError(name);
      }
      return [...new Set(value as string[])];
  }
}

export function parseValuationRequest(text: string): ValuationRequest {
  if (new TextEncoder().encode(text).length > VALUATION_LIMITS.bodyBytes) throw new ValidationError("size");
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    throw new ValidationError("json");
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) throw new ValidationError("json");
  const { protocol, user, asset, ...rest } = body as Record<string, unknown>;
  if (Object.keys(rest).length) throw new ValidationError("field");
  if (protocol !== PROTOCOL_VERSION) throw new ValidationError("protocol");
  if (user !== undefined && (typeof user !== "string" || !isValidUserId(user))) throw new ValidationError("user");
  if (typeof asset !== "object" || asset === null || Array.isArray(asset)) throw new ValidationError("asset");

  const raw = asset as Record<string, unknown>;
  const kind = raw.kind;
  if (typeof kind !== "string" || !(ASSET_KINDS as readonly string[]).includes(kind)) throw new ValidationError("kind");
  if (typeof raw.country !== "string" || !/^[A-Z]{2}$/.test(raw.country)) throw new ValidationError("country");
  const rules = KIND_FIELDS[kind as AssetKind];

  const parsed: Record<string, unknown> = { kind, country: raw.country };
  for (const [name, value] of Object.entries(raw)) {
    if (name === "kind" || name === "country" || value === null || value === undefined) continue;
    const rule = FIELDS[name as keyof typeof FIELDS];
    if (!rule) throw new ValidationError("field");
    if (!rules.allowed.includes(name)) throw new ValidationError(`${name}_for_kind`);
    parsed[name] = checkField(name, rule, value);
  }
  for (const anyOf of rules.required) {
    if (!anyOf.some((name) => parsed[name] !== undefined)) throw new ValidationError(anyOf.join("_or_"));
  }
  if (typeof parsed.year === "number" && parsed.year > thisYear() + 1) throw new ValidationError("year");
  if (typeof parsed.year_built === "number" && parsed.year_built > thisYear() + 5) throw new ValidationError("year_built");
  return { protocol: PROTOCOL_VERSION, user: user as string | undefined, asset: parsed as unknown as AssetDescription };
}

// MARK: - The model call

/** Models whose web search filters its results with code before they reach the context. */
const DYNAMIC_FILTERING_MODELS = new Set([
  "claude-fable-5-1",
  "claude-fable-5",
  "claude-opus-5-5",
  "claude-opus-5",
  "claude-opus-4-8",
  "claude-opus-4-7",
  "claude-opus-4-6",
  "claude-sonnet-5-5",
  "claude-sonnet-5",
  "claude-sonnet-4-6",
]);

/** Countries web search refuses in `user_location` (a 400, "Country code KZ is not supported"),
 * and those learned from such a refusal while this isolate runs: the place stays in the asset
 * the model reads, and so in its queries. */
const LOCATION_UNSUPPORTED = new Set(["KZ"]);

export const supportsLocation = (country: string) => !LOCATION_UNSUPPORTED.has(country);

/** A 400 naming the country of `user_location` as unsupported. */
export function isLocationRefusal(error: unknown): boolean {
  const e = error as { status?: unknown; message?: unknown };
  return e?.status === 400 && typeof e.message === "string" && /country code \w+ is not supported/i.test(e.message);
}

export function webSearchTool(model: string, maxUses: number, asset: AssetDescription, withLocation = supportsLocation(asset.country)): Anthropic.Beta.BetaToolUnion {
  const user_location: Anthropic.Beta.BetaUserLocation = {
    type: "approximate",
    country: asset.country,
    ...(asset.city ? { city: asset.city } : {}),
    ...(asset.region ? { region: asset.region } : {}),
  };
  const located = withLocation ? { user_location } : {};
  return DYNAMIC_FILTERING_MODELS.has(model)
    ? { type: "web_search_20260209", name: "web_search", max_uses: maxUses, ...located }
    : { type: "web_search_20250305", name: "web_search", max_uses: maxUses, ...located };
}

const nullable = (schema: Record<string, unknown>) => ({ anyOf: [schema, { type: "null" }] });

// Strict: the input always parses. Seven nullables, under the API's limit of 16 per request.
export const REPORT_LISTINGS_TOOL: Anthropic.Beta.BetaTool = {
  name: REPORT_LISTINGS,
  description:
    "Reports the listings found in the search results, once, at the end. The app checks each one against the results and computes the value; nothing here is shown as is.",
  strict: true,
  input_schema: {
    type: "object",
    additionalProperties: false,
    required: ["listings", "site_averages"],
    properties: {
      listings: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["source_url", "price", "currency", "deal", "size_m2", "land_ares", "rooms", "year", "mileage_km", "district", "new_building"],
          properties: {
            source_url: { type: "string", description: "The URL of the search result the listing was seen in, copied exactly" },
            price: { type: "number", description: "The asking price as written, in its currency" },
            currency: { type: "string", description: "ISO 4217" },
            deal: { type: "string", enum: ["sale", "rent"] },
            size_m2: nullable({ type: "number", description: "Floor area in square metres (square feet × 0.0929)" }),
            land_ares: nullable({ type: "number", description: "Land in ares: one sotka is one are, a hectare is 100" }),
            rooms: nullable({ type: "integer" }),
            year: nullable({ type: "integer", description: "Year built, or a vehicle's model year" }),
            mileage_km: nullable({ type: "number", description: "Kilometres (miles × 1.609)" }),
            district: nullable({ type: "string" }),
            new_building: nullable({ type: "boolean" }),
          },
        },
      },
      site_averages: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: ["source_url", "value", "currency", "per"],
          properties: {
            source_url: { type: "string" },
            value: { type: "number" },
            currency: { type: "string", description: "ISO 4217" },
            per: { type: "string", enum: ["total", "m2", "are"] },
          },
        },
      },
    },
  },
};

export const VALUATION_SYSTEM_PROMPT = `You find listings for sale that are comparable to one asset, so that an app can estimate what it is worth. You never estimate the value yourself.

1. Search with web_search for current listings of comparable assets for sale in the asset's country and place: the same kind, and as close as the description allows (district or complex, rooms, size, year; for a vehicle make, model, generation, year, mileage). Write each query in the language of that country's listing sites, the way a local buyer would (Russian for Kazakhstan, Turkish for Turkey, German for Germany), and prefer the country's big listing sites and their search result pages. Unless the first search already showed ten or more such listings, search again with other wording or on another of the country's listing sites: the value needs many listings.
2. Then call report_listings once, with every listing for sale you saw in the results that is the same kind of asset, close or not: the app filters them. For each listing: the asking price and its currency as written, sale or rent, the size in square metres, land in ares, rooms as that country's listings count them (the first number of 2+1 in Turkey, bedrooms in the UK and the US), year, mileage in kilometres, the district when shown, and source_url: the URL of the search result you saw it in, copied exactly. One results page can hold several listings: report each one with that page's URL.
3. Report only what the results show. Never invent a listing, a price, a size or a URL. Copy each price in full as a number, minding the country's thousands separators ("5.150.000 TL" is 5150000, "1,250,000" is 1250000); never shorten it. Skip listings without a price, and those that are not a whole asset for sale at a fixed price: a share or shared ownership, an auction, rent to own, a new development's "from" price. Never report sellers' names, phone numbers or exact addresses.
4. A site's own average or index ("average price of a two-room flat in the district", "price per m² in the city") is not a listing: put it in site_averages.
5. If nothing relevant was found, call report_listings with empty lists. Write no other text.`;

export interface ValuationConfig {
  /** Asked again when the first model finds too few listings or declines; none when empty. */
  fallbackModel?: string;
  model: string;
  effort: Config["effort"];
  maxSearches: number;
}

export function valuationConfig(config: Config): ValuationConfig {
  return {
    model: config.valuationModel,
    effort: config.valuationEffort,
    maxSearches: config.valuationMaxSearches,
    ...(config.valuationFallbackModel && config.valuationFallbackModel !== config.valuationModel ? { fallbackModel: config.valuationFallbackModel } : {}),
  };
}

/** `searchesLeft`: a later call of the same valuation keeps the search tool (its earlier calls are
 * in the history) with what is left of the limit, at least one. */
export function buildValuationParams(
  config: ValuationConfig,
  asset: AssetDescription,
  now: Date,
  searchesLeft = config.maxSearches,
  withLocation = supportsLocation(asset.country),
): Params {
  const tools: Anthropic.Beta.BetaToolUnion[] = [webSearchTool(config.model, Math.max(1, searchesLeft), asset, withLocation), REPORT_LISTINGS_TOOL];
  return {
    model: config.model,
    max_tokens: 8000,
    system: [{ type: "text", text: VALUATION_SYSTEM_PROMPT }],
    tools,
    // Forced tool choice is a 400 on the current models: the prompt asks for report_listings.
    tool_choice: { type: "auto" },
    thinking: { type: "adaptive" },
    output_config: { effort: config.effort },
    messages: [
      {
        role: "user",
        content: [{ type: "text", text: `Today is ${now.toISOString().slice(0, 10)}.\nThe asset:\n${JSON.stringify(asset, null, 1)}` }],
      },
    ],
  };
}

/** One model call; the endpoint streams it, tests script it. */
export type ModelCall = (params: Params) => Promise<Message>;

export interface ValuationUsage {
  input_tokens: number;
  output_tokens: number;
  cache_read_input_tokens: number;
  cache_creation_input_tokens: number;
  searches: number;
}

export interface SearchOutcome {
  report?: Report;
  results: Map<string, SearchResult>;
  queries: string[];
  usage: ValuationUsage;
  calls: number;
  /** The model declined (stop_reason "refusal"). */
  refused: boolean;
  /** Each call's stop reason and any text the model wrote (it should write none): for the eval,
   * never sent to the phone or logged. */
  trace: { stop_reason: string | null; text: string }[];
}

const NUDGE = "Call report_listings now with the listings you found.";

/** Searches until the model calls report_listings: a paused turn goes on, a turn that ended without the report is asked for it once. At most three calls. A location the search refuses is dropped and the call made again. */
export async function searchListings(call: ModelCall, config: ValuationConfig, asset: AssetDescription, now: Date): Promise<SearchOutcome> {
  let withLocation = supportsLocation(asset.country);
  const first = buildValuationParams(config, asset, now, config.maxSearches, withLocation);
  const messages: MessageParam[] = [...first.messages];
  const content: ContentBlock[] = [];
  const usage: ValuationUsage = { input_tokens: 0, output_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, searches: 0 };
  let calls = 0;
  let nudged = false;
  let refused = false;
  let report: Report | undefined;
  const trace: SearchOutcome["trace"] = [];

  while (calls < 3) {
    const params = { ...buildValuationParams(config, asset, now, config.maxSearches - usage.searches, withLocation), messages };
    let message: Message;
    try {
      message = await call(params);
    } catch (error) {
      if (!withLocation || !isLocationRefusal(error)) throw error;
      LOCATION_UNSUPPORTED.add(asset.country);
      withLocation = false;
      message = await call({ ...buildValuationParams(config, asset, now, config.maxSearches - usage.searches, false), messages });
    }
    calls += 1;
    usage.input_tokens += message.usage.input_tokens;
    usage.output_tokens += message.usage.output_tokens;
    usage.cache_read_input_tokens += message.usage.cache_read_input_tokens ?? 0;
    usage.cache_creation_input_tokens += message.usage.cache_creation_input_tokens ?? 0;
    usage.searches += message.usage.server_tool_use?.web_search_requests ?? 0;
    content.push(...message.content);
    trace.push({
      stop_reason: message.stop_reason,
      text: message.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("\n").slice(0, 2000),
    });
    if (message.stop_reason === "refusal") {
      refused = true;
      break;
    }
    report = reportOf(message.content);
    if (report) break;
    messages.push({ role: "assistant", content: message.content as Anthropic.Beta.BetaContentBlockParam[] });
    if (message.stop_reason === "pause_turn") continue;
    if (nudged) break;
    nudged = true;
    messages.push({ role: "user", content: [{ type: "text", text: NUDGE }] });
  }
  return { report, results: searchResults(content), queries: queriesOf(content), usage, calls, refused, trace };
}

export interface Valuation {
  result: ValuationResult;
  /** The model whose search the result comes from. */
  model: string;
  /** Every search made, the first model's first. */
  searches: { model: string; outcome: SearchOutcome }[];
  usedFallback: boolean;
}

/** The value of an asset: the first model's search, and when it finds too few listings (or
 * declines) the fallback model's, whose result then stands. */
export async function valuate(call: ModelCall, config: ValuationConfig, asset: AssetDescription, now: Date): Promise<Valuation> {
  const first = await searchListings(call, config, asset, now);
  const firstResult = computeValuation(asset, first.report, first.results, now);
  const searches = [{ model: config.model, outcome: first }];
  if (!config.fallbackModel || (firstResult.status === "ok" && !first.refused)) {
    return { result: firstResult, model: config.model, searches, usedFallback: false };
  }
  const second = await searchListings(call, { ...config, model: config.fallbackModel }, asset, now);
  searches.push({ model: config.fallbackModel, outcome: second });
  const secondResult = computeValuation(asset, second.report, second.results, now);
  // A refused or empty second search does not hide what the first one found.
  const useSecond = !second.refused && (secondResult.status === "ok" || first.refused);
  return useSecond
    ? { result: secondResult, model: config.fallbackModel, searches, usedFallback: true }
    : { result: firstResult, model: config.model, searches, usedFallback: true };
}

// MARK: - Reading the response

export interface SearchResult {
  url: string;
  title: string;
}

export interface ReportedListing {
  source_url: string;
  price: number;
  currency: string;
  deal: "sale" | "rent";
  size_m2: number | null;
  land_ares: number | null;
  rooms: number | null;
  year: number | null;
  mileage_km: number | null;
  district: string | null;
  new_building: boolean | null;
}

export interface Report {
  listings: ReportedListing[];
  site_averages: { source_url: string; value: number; currency: string; per: "total" | "m2" | "are" }[];
}

/** A URL as two spellings of it compare: no fragment, no `www.` or `m.`, decoded, no trailing slash. */
export function normalizeUrl(raw: string): string | undefined {
  let url: URL;
  try {
    url = new URL(raw.trim());
  } catch {
    return undefined;
  }
  if (url.protocol !== "https:" && url.protocol !== "http:") return undefined;
  const host = url.hostname.toLowerCase().replace(/^(www|m)\./, "");
  let rest = `${url.pathname.replace(/\/+$/, "")}${url.search}`;
  try {
    rest = decodeURIComponent(rest);
  } catch {
    // Keep it encoded.
  }
  return `${host}${rest}`;
}

/** Every web search result in the content, by normalized URL. */
export function searchResults(content: ContentBlock[]): Map<string, SearchResult> {
  const results = new Map<string, SearchResult>();
  for (const block of content) {
    if (block.type !== "web_search_tool_result" || !Array.isArray(block.content)) continue;
    for (const result of block.content) {
      const key = normalizeUrl(result.url);
      if (key && !results.has(key)) results.set(key, { url: result.url, title: result.title });
    }
  }
  return results;
}

export function queriesOf(content: ContentBlock[]): string[] {
  return content.flatMap((block) =>
    block.type === "server_tool_use" && block.name === "web_search" && typeof block.input.query === "string" ? [block.input.query] : [],
  );
}

export function reportOf(content: ContentBlock[]): Report | undefined {
  const use = content.find((block): block is Anthropic.Beta.BetaToolUseBlock => block.type === "tool_use" && block.name === REPORT_LISTINGS);
  if (!use) return undefined;
  const input = use.input as Partial<Report>;
  return {
    listings: Array.isArray(input.listings) ? input.listings : [],
    site_averages: Array.isArray(input.site_averages) ? input.site_averages : [],
  };
}

// MARK: - The value

export type Accuracy = "high" | "medium" | "low";

export interface UsedListing {
  title: string;
  url: string;
  site: string;
  price: number;
  currency: string;
  size_m2: number | null;
  land_ares: number | null;
  rooms: number | null;
  year: number | null;
  mileage_km: number | null;
}

export interface ValuationResult {
  status: "ok" | "insufficient";
  /** Why there is no value: fewer than three comparables, or no report at all. */
  reason?: "few_listings" | "no_report";
  /** The market's currency, the one most comparables are priced in; the phone converts. */
  currency: string | null;
  /** The median, rounded to three significant digits; low and high are the quartiles. */
  value: number | null;
  low: number | null;
  high: number | null;
  accuracy: Accuracy | null;
  /** per_unit: the median price of a square metre (or an are) times the asset's size. */
  basis: "per_unit" | "price" | null;
  per_unit: { unit: "m2" | "are"; median: number; low: number; high: number } | null;
  /** Comparables in the value. */
  count: number;
  listings: UsedListing[];
  site_averages: { title: string; url: string; value: number; currency: string; per: "total" | "m2" | "are" }[];
  /** Listings left out, by reason. */
  excluded: Record<string, number>;
  searched_at: string;
}

export const MIN_COMPARABLES = 3;
/** Prices of comparable things span less than this from the cheapest to the dearest; a group
 * this far from the main one is misread (a power of ten) or another kind of thing. */
const CLUSTER_SPAN = 6.25;
const LISTINGS_RETURNED = 12;

interface Candidate {
  listing: ReportedListing;
  result: SearchResult;
}

/** The bounds of the largest group of values within CLUSTER_SPAN of each other; of two as large,
 * the dearer (misreads drop digits far more often than they add them). */
export function densestGroup(values: number[]): [number, number] {
  const sorted = [...values].sort((a, b) => a - b);
  let best: [number, number] = [sorted[0]!, sorted[0]!];
  let bestCount = 0;
  let end = 0;
  for (let start = 0; start < sorted.length; start++) {
    end = Math.max(end, start);
    while (end + 1 < sorted.length && sorted[end + 1]! <= sorted[start]! * CLUSTER_SPAN) end++;
    const count = end - start + 1;
    if (count >= bestCount) {
      bestCount = count;
      best = [sorted[start]!, sorted[end]!];
    }
  }
  return best;
}

export function quantile(sorted: number[], p: number): number {
  if (!sorted.length) return Number.NaN;
  const index = (sorted.length - 1) * p;
  const lo = Math.floor(index);
  const hi = Math.min(lo + 1, sorted.length - 1);
  return sorted[lo]! + (sorted[hi]! - sorted[lo]!) * (index - lo);
}

/** Three significant digits: an estimate from listings has no more. */
export const round3 = (value: number) => (value === 0 ? 0 : Number(value.toPrecision(3)));

const within = (value: number, target: number, share: number) => Math.abs(value - target) <= target * share;

function hostOf(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, "");
  } catch {
    return "";
  }
}

export function computeValuation(asset: AssetDescription, report: Report | undefined, results: Map<string, SearchResult>, now: Date): ValuationResult {
  const excluded: Record<string, number> = {};
  const drop = (reason: string) => {
    excluded[reason] = (excluded[reason] ?? 0) + 1;
  };
  const empty = (reason: ValuationResult["reason"]): ValuationResult => ({
    status: "insufficient",
    reason,
    currency: null,
    value: null,
    low: null,
    high: null,
    accuracy: null,
    basis: null,
    per_unit: null,
    count: 0,
    listings: [],
    site_averages: [],
    excluded,
    searched_at: now.toISOString(),
  });
  if (!report) return empty("no_report");

  // Only listings seen in the search results, for sale, priced, once each.
  const seen = new Set<string>();
  let candidates: Candidate[] = [];
  for (const listing of report.listings) {
    const key = normalizeUrl(listing.source_url ?? "");
    const result = key ? results.get(key) : undefined;
    if (!result) {
      drop("unverified_url");
      continue;
    }
    if (listing.deal !== "sale") {
      drop("rent");
      continue;
    }
    if (!(typeof listing.price === "number" && Number.isFinite(listing.price) && listing.price > 0)) {
      drop("no_price");
      continue;
    }
    const currency = String(listing.currency ?? "").toUpperCase();
    if (!/^[A-Z]{3}$/.test(currency)) {
      drop("currency");
      continue;
    }
    const identity = [listing.price, listing.size_m2 ?? listing.land_ares ?? "", listing.mileage_km ?? "", listing.year ?? "", listing.rooms ?? ""].join("|");
    if (seen.has(identity)) {
      drop("duplicate");
      continue;
    }
    seen.add(identity);
    candidates.push({ listing: { ...listing, currency }, result });
  }

  // The market's currency: the one most listings are priced in.
  const counts = new Map<string, number>();
  for (const c of candidates) counts.set(c.listing.currency, (counts.get(c.listing.currency) ?? 0) + 1);
  const currency = [...counts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  candidates = candidates.filter((c) => {
    if (c.listing.currency === currency) return true;
    drop("currency");
    return false;
  });

  const { chosen, values, basis, unit, size, relaxed } = comparables(asset, candidates, drop);

  let kept = chosen.map((c, i) => ({ c, v: values[i]! }));
  // Prices misread by a power of ten, or another kind of thing, make a group of their own, as
  // large as the real one at times (Tukey's fences and the median then fail): the largest group
  // within CLUSTER_SPAN is the market.
  if (kept.length >= MIN_COMPARABLES) {
    const [lo, hi] = densestGroup(kept.map((k) => k.v));
    kept = kept.filter((k) => {
      if (k.v >= lo && k.v <= hi) return true;
      drop("outside_cluster");
      return false;
    });
  }
  // Outliers by Tukey's fences, once there are enough to tell.
  if (kept.length >= 4) {
    const sorted = kept.map((k) => k.v).sort((a, b) => a - b);
    const q1 = quantile(sorted, 0.25);
    const q3 = quantile(sorted, 0.75);
    const fence = 1.5 * (q3 - q1);
    kept = kept.filter((k) => {
      if (k.v >= q1 - fence && k.v <= q3 + fence) return true;
      drop("outlier");
      return false;
    });
  }

  const siteAverages = report.site_averages.flatMap((average) => {
    const key = normalizeUrl(average.source_url ?? "");
    const result = key ? results.get(key) : undefined;
    if (!result || !(average.value > 0)) return [];
    return [{ title: result.title, url: result.url, value: average.value, currency: String(average.currency).toUpperCase(), per: average.per }];
  });

  if (kept.length < MIN_COMPARABLES || !currency) {
    return { ...empty("few_listings"), currency: currency ?? null, count: kept.length, site_averages: siteAverages };
  }

  const sorted = kept.map((k) => k.v).sort((a, b) => a - b);
  const median = quantile(sorted, 0.5);
  const q1 = quantile(sorted, 0.25);
  const q3 = quantile(sorted, 0.75);
  const spread = Math.max((median - q1) / median, (q3 - median) / median);
  let accuracy: Accuracy = kept.length >= 8 && spread <= 0.1 ? "high" : kept.length >= 5 && spread <= 0.2 ? "medium" : "low";
  if (kept.length <= 4) accuracy = "low";
  if ((relaxed || asset.kind === "other") && accuracy === "high") accuracy = "medium";

  const scale = basis === "per_unit" ? size! : 1;
  return {
    status: "ok",
    currency,
    value: round3(median * scale),
    low: round3(q1 * scale),
    high: round3(q3 * scale),
    accuracy,
    basis,
    per_unit: basis === "per_unit" ? { unit: unit!, median: round3(median), low: round3(q1), high: round3(q3) } : null,
    count: kept.length,
    listings: kept
      .sort((a, b) => a.v - b.v)
      .slice(0, LISTINGS_RETURNED)
      .map(({ c }) => ({
        title: c.result.title,
        url: c.result.url,
        site: hostOf(c.result.url),
        price: c.listing.price,
        currency: c.listing.currency,
        size_m2: c.listing.size_m2,
        land_ares: c.listing.land_ares,
        rooms: c.listing.rooms,
        year: c.listing.year,
        mileage_km: c.listing.mileage_km,
      })),
    site_averages: siteAverages,
    excluded,
    searched_at: now.toISOString(),
  };
}

interface Comparables {
  chosen: Candidate[];
  /** What each one is compared by: its price per unit, or its price. */
  values: number[];
  basis: "per_unit" | "price";
  unit?: "m2" | "are";
  size?: number;
  /** The close match was too thin and a wider one was taken. */
  relaxed: boolean;
}

/** The listings close enough to the asset to price it, widest last: same size within 25% (then 40%), else by price among the same rooms; a vehicle of the same year ±1, by mileage ±40 000 km when there are enough. */
function comparables(asset: AssetDescription, candidates: Candidate[], drop: (reason: string) => void): Comparables {
  if (asset.kind === "vehicle") {
    const sameYear = candidates.filter((c) => {
      if (c.listing.year !== null && asset.year !== undefined && Math.abs(c.listing.year - asset.year) <= 1) return true;
      drop("year");
      return false;
    });
    if (asset.mileage_km !== undefined) {
      const close = sameYear.filter((c) => c.listing.mileage_km !== null && Math.abs(c.listing.mileage_km - asset.mileage_km!) <= 40_000);
      if (close.length >= MIN_COMPARABLES) {
        for (let i = close.length; i < sameYear.length; i++) drop("mileage");
        return { chosen: close, values: close.map((c) => c.listing.price), basis: "price", relaxed: false };
      }
      return { chosen: sameYear, values: sameYear.map((c) => c.listing.price), basis: "price", relaxed: true };
    }
    return { chosen: sameYear, values: sameYear.map((c) => c.listing.price), basis: "price", relaxed: false };
  }

  if (asset.kind === "other") {
    return { chosen: candidates, values: candidates.map((c) => c.listing.price), basis: "price", relaxed: false };
  }

  const unit = asset.kind === "land" ? "are" : "m2";
  const size = asset.kind === "land" ? asset.land_ares : asset.area_m2;
  const sizeOf = (c: Candidate) => (unit === "are" ? c.listing.land_ares : c.listing.size_m2);

  // Rooms count when both sides know them.
  const sameRooms = candidates.filter((c) => {
    if (asset.rooms === undefined || c.listing.rooms === null || c.listing.rooms === asset.rooms) return true;
    drop("rooms");
    return false;
  });

  // The listings that name the same rooms, priced as a whole: what is left when sizes are few.
  const sameRoomsKnown = asset.rooms === undefined ? sameRooms : sameRooms.filter((c) => c.listing.rooms === asset.rooms);

  if (size !== undefined) {
    for (const [share, relaxed] of [
      [0.25, false],
      [0.4, true],
    ] as const) {
      const close = sameRooms.filter((c) => {
        const s = sizeOf(c);
        return s !== null && s > 0 && within(s, size, share);
      });
      // Sizes on only a few of many listings (a detail page here and there, as in the UK) would
      // price the asset by those few: then the many same-room listings are the better sample.
      const fewOfMany = sameRoomsKnown.length >= 5 && close.length * 2 < sameRoomsKnown.length;
      if (close.length >= MIN_COMPARABLES && !fewOfMany) {
        for (let i = close.length; i < sameRooms.length; i++) drop("size");
        return { chosen: close, values: close.map((c) => c.listing.price / sizeOf(c)!), basis: "per_unit", unit, size, relaxed };
      }
    }
  }

  // Sizes too few (listings abroad often give bedrooms, not square metres): by price, among
  // the same rooms when the asset's are known.
  const byPrice = sameRooms.filter((c) => {
    if (asset.rooms === undefined || c.listing.rooms === asset.rooms) return true;
    drop("rooms");
    return false;
  });
  return { chosen: byPrice, values: byPrice.map((c) => c.listing.price), basis: "price", relaxed: true };
}
