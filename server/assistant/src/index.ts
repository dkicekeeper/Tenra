import Anthropic from "@anthropic-ai/sdk";
import { AttestError, checkAssertion, isValidKeyId, issueChallenge, registerKey } from "./appattest";
import { buildParams, donePayload, errorPayload } from "./claude";
import { readConfig, type Config, type Env } from "./config";
import { resolveTier, UpstreamError } from "./entitlement";
import { PROMPT_VERSION } from "./prompt";
import { RENDER_REPLY } from "./tools";
import { consumeCall, consumeValuation, refund, type Tier } from "./quota";
import { isValidUserId, parseTurnRequest, PROTOCOL_VERSION, ValidationError } from "./validate";
import { parseValuationRequest, valuate, VALUATION_PROMPT_VERSION, valuationConfig } from "./valuation";

// POST /v1/turn — one model call of the assistant loop. The app runs the loop: it sends the
// conversation, executes the tools Claude asks for on the phone, and calls again with the
// results. Response: server-sent events
//   tool  {name}            a tool call started (for the "thinking" steps in the UI)
//   text  {text}            plain text delta (not shown: replies go through render_reply)
//   reply {json}            a piece of render_reply's input as the model writes it, so the app
//                           shows the reply's text while it streams (older apps ignore it)
//   done  {content, ...}    the assistant turn to append verbatim, plus usage and quota
//   error {code, retryable}
//
// POST /v1/valuation — what an asset is worth by comparable listings found with web search
// (src/valuation.ts): one JSON answer, off until VALUATION_ENABLED. Same App Attest, user and
// Pro rules as a turn, its own monthly count.
//
// Every turn must come from the real app: it carries an App Attest assertion over its body
// (x-tenra-key, x-tenra-assertion). The user id counts only inside that signed body, so a
// copied Pro customer's id alone spends nothing. Free answers are counted per attested key,
// Pro calls per customer. GET /v1/attest/challenge and POST /v1/attest register that key once
// per install.
//
// Nothing about the conversation is logged: only status codes and error codes.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

const fail = (status: number, code: string, extra: Record<string, unknown> = {}) => json({ error: code, ...extra }, status);

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v1/health") {
      const valuation = readConfig(env).valuationEnabled ? VALUATION_PROMPT_VERSION : null;
      return json({ ok: true, protocol: PROTOCOL_VERSION, prompt: PROMPT_VERSION, valuation });
    }
    const routes = ["/v1/turn", "/v1/valuation", "/v1/attest", "/v1/attest/challenge"];
    if (!routes.includes(url.pathname)) return fail(404, "not_found");

    const config = readConfig(env);
    if (!config.enabled) return fail(503, "disabled");

    // request.cf is set on every request; the cf-ipcountry header only with IP Geolocation on
    // the zone, which a workers.dev route doesn't have.
    const country = ((request.cf?.country as string | undefined) ?? request.headers.get("cf-ipcountry") ?? undefined)?.toUpperCase();
    if (country && config.blockedCountries.has(country)) return fail(451, "region_unavailable");

    if (url.pathname === "/v1/attest/challenge") {
      if (request.method !== "GET") return fail(405, "method");
      return json({ challenge: await issueChallenge(env.QUOTA) });
    }
    if (request.method !== "POST") return fail(405, "method");
    if (url.pathname === "/v1/attest") return attest(request, env, config.appId);
    if (url.pathname === "/v1/valuation") return valuation(request, env, config);

    const userId = request.headers.get("x-tenra-user");
    if (!isValidUserId(userId)) return fail(401, "user");

    const bytes = new Uint8Array(await request.arrayBuffer());
    let turn;
    try {
      turn = parseTurnRequest(new TextDecoder().decode(bytes));
    } catch (error) {
      if (error instanceof ValidationError) return fail(400, "invalid", { reason: error.code });
      throw error;
    }

    const caller = await identify(request, env, config, bytes, turn.user, userId);
    if (caller instanceof Response) return caller;
    const { tier, quotaId } = caller;

    const quota = await consumeCall(env.QUOTA, quotaId, tier, config);
    if (!quota.allowed) return fail(429, quota.reason === "global" ? "busy" : "quota", { tier, used: quota.used, limit: quota.limit });

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
    const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();
    const send = (event: string, data: unknown) =>
      writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)).catch(() => undefined);

    // Set by the first event of the model's stream. A call that fails before it (Anthropic down,
    // overloaded, or refusing the request) produced nothing and costs nothing: its count is given
    // back. One that fails mid-answer keeps it, since part of it was generated.
    let started = false;
    ctx.waitUntil(
      (async () => {
        try {
          const stream = client.beta.messages.stream(buildParams(config, turn.messages, tier));
          // The content block that is render_reply's call, while it streams.
          let replyIndex: number | undefined;
          for await (const event of stream) {
            started = true;
            if (event.type === "content_block_start" && event.content_block.type === "tool_use") {
              if (event.content_block.name === RENDER_REPLY) replyIndex = event.index;
              await send("tool", { name: event.content_block.name });
            } else if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
              await send("text", { text: event.delta.text });
            } else if (event.type === "content_block_delta" && event.delta.type === "input_json_delta" && event.index === replyIndex) {
              await send("reply", { json: event.delta.partial_json });
            }
          }
          const message = await stream.finalMessage();
          await send("done", { ...donePayload(message), tier, quota: { used: quota.used, limit: quota.limit } });
        } catch (error) {
          const payload = errorPayload(error);
          console.log(`turn error ${payload.code}${error instanceof Anthropic.APIError ? ` ${error.status}` : ""}${started ? "" : " refunded"}`);
          await send("error", payload);
          if (!started && quota.charge) await refund(env.QUOTA, quota.charge);
        } finally {
          await writer.close().catch(() => undefined);
        }
      })(),
    );

    return new Response(readable, {
      headers: { "content-type": "text/event-stream", "cache-control": "no-store", "x-tenra-prompt": PROMPT_VERSION },
    });
  },
} satisfies ExportedHandler<Env>;

interface Caller {
  tier: Tier;
  /** Free calls count per attested key, Pro ones per customer. */
  quotaId: string;
}

/** Checks the body's App Attest assertion, then the Pro status of the user named inside it. */
async function identify(request: Request, env: Env, config: Config, bytes: Uint8Array, bodyUser: string | undefined, userId: string): Promise<Caller | Response> {
  // The body must be signed by a key attested on a real device, Pro or not. Checked before
  // anything that costs a RevenueCat call or a KV write, so a request that is not from the
  // app stops here.
  const keyId = request.headers.get("x-tenra-key");
  const assertion = request.headers.get("x-tenra-assertion");
  if (!isValidKeyId(keyId) || !assertion || assertion.length > 4096) return fail(401, "attest", { reason: "missing" });
  try {
    await checkAssertion(env.QUOTA, keyId, assertion, bytes, config.appId);
  } catch (error) {
    if (error instanceof AttestError) return fail(401, "attest", { reason: error.reason });
    throw error;
  }

  // Pro is looked up only for the user id inside the signed body: the header alone is a claim
  // anyone could copy from someone's Support ID. Apps before 1.6 (build 27) don't sign it and
  // count as free.
  if (bodyUser !== undefined && bodyUser !== userId) return fail(401, "user");
  let tier: Tier = "free";
  if (bodyUser !== undefined) {
    try {
      tier = await resolveTier(env.QUOTA, env.REVENUECAT_SECRET_KEY, bodyUser);
    } catch (error) {
      if (error instanceof UpstreamError) {
        console.log(`entitlement ${error.status}`);
        return fail(502, "entitlement_unavailable");
      }
      throw error;
    }
  }
  return { tier, quotaId: tier === "free" ? `key:${keyId}` : userId };
}

async function valuation(request: Request, env: Env, config: Config): Promise<Response> {
  if (!config.valuationEnabled) return fail(503, "disabled");
  const userId = request.headers.get("x-tenra-user");
  if (!isValidUserId(userId)) return fail(401, "user");

  const bytes = new Uint8Array(await request.arrayBuffer());
  let body;
  try {
    body = parseValuationRequest(new TextDecoder().decode(bytes));
  } catch (error) {
    if (error instanceof ValidationError) return fail(400, "invalid", { reason: error.code });
    throw error;
  }

  const caller = await identify(request, env, config, bytes, body.user, userId);
  if (caller instanceof Response) return caller;
  const { tier, quotaId } = caller;

  const quota = await consumeValuation(env.QUOTA, quotaId, tier, config);
  if (!quota.allowed) return fail(429, quota.reason === "global" ? "busy" : "quota", { tier, used: quota.used, limit: quota.limit });

  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
  const now = new Date();
  try {
    const valuation = await valuate((params) => client.beta.messages.stream(params).finalMessage(), valuationConfig(config), body.asset, now);
    if (valuation.searches.every((s) => s.outcome.refused)) return fail(422, "refused");
    return json({
      ...valuation.result,
      searches: valuation.searches.reduce((n, s) => n + s.outcome.usage.searches, 0),
      model: valuation.model,
      fallback: valuation.usedFallback,
      prompt: VALUATION_PROMPT_VERSION,
      tier,
      quota: { used: quota.used, limit: quota.limit },
    });
  } catch (error) {
    const payload = errorPayload(error);
    console.log(`valuation error ${payload.code}${error instanceof Anthropic.APIError ? ` ${error.status}` : ""}`);
    return fail(502, "upstream", { ...payload });
  }
}

async function attest(request: Request, env: Env, appId: string): Promise<Response> {
  let input: { keyId?: unknown; attestation?: unknown; challenge?: unknown };
  try {
    const text = await request.text();
    if (text.length > 64 * 1024) return fail(400, "invalid", { reason: "size" });
    input = JSON.parse(text);
  } catch {
    return fail(400, "invalid", { reason: "json" });
  }
  const { keyId, attestation, challenge } = input;
  if (typeof keyId !== "string" || !isValidKeyId(keyId) || typeof attestation !== "string" || typeof challenge !== "string") {
    return fail(400, "invalid", { reason: "fields" });
  }
  try {
    const stored = await registerKey(env.QUOTA, { keyId, attestation, challenge }, { appId });
    return json({ ok: true, environment: stored.environment });
  } catch (error) {
    if (error instanceof AttestError) {
      console.log(`attest ${error.reason}`);
      return fail(400, "attestation", { reason: error.reason });
    }
    throw error;
  }
}
