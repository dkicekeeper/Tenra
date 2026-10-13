import Anthropic from "@anthropic-ai/sdk";
import { buildParams, donePayload, errorPayload } from "./claude";
import { readConfig, type Env } from "./config";
import { resolveTier, UpstreamError } from "./entitlement";
import { PROMPT_VERSION } from "./prompt";
import { consumeCall } from "./quota";
import { isValidUserId, parseTurnRequest, PROTOCOL_VERSION, ValidationError } from "./validate";

// POST /v1/turn — one model call of the assistant loop. The app runs the loop: it sends the
// conversation, executes the tools Claude asks for on the phone, and calls again with the
// results. Response: server-sent events
//   tool  {name}            a tool call started (for the "thinking" steps in the UI)
//   text  {text}            plain text delta (not shown: replies go through render_reply)
//   done  {content, ...}    the assistant turn to append verbatim, plus usage and quota
//   error {code, retryable}
//
// Nothing about the conversation is logged: only status codes and error codes.

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

const fail = (status: number, code: string, extra: Record<string, unknown> = {}) => json({ error: code, ...extra }, status);

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname === "/v1/health") return json({ ok: true, protocol: PROTOCOL_VERSION, prompt: PROMPT_VERSION });
    if (url.pathname !== "/v1/turn") return fail(404, "not_found");
    if (request.method !== "POST") return fail(405, "method");

    const config = readConfig(env);
    if (!config.enabled) return fail(503, "disabled");

    const country = request.headers.get("cf-ipcountry")?.toUpperCase();
    if (country && config.blockedCountries.has(country)) return fail(451, "region_unavailable");

    const userId = request.headers.get("x-tenra-user");
    if (!isValidUserId(userId)) return fail(401, "user");

    let turn;
    try {
      turn = parseTurnRequest(await request.text());
    } catch (error) {
      if (error instanceof ValidationError) return fail(400, "invalid", { reason: error.code });
      throw error;
    }

    let tier;
    try {
      tier = await resolveTier(env.QUOTA, env.REVENUECAT_SECRET_KEY, userId);
    } catch (error) {
      if (error instanceof UpstreamError) {
        console.log(`entitlement ${error.status}`);
        return fail(502, "entitlement_unavailable");
      }
      throw error;
    }

    const quota = await consumeCall(env.QUOTA, userId, tier, config);
    if (!quota.allowed) return fail(429, quota.reason === "global" ? "busy" : "quota", { tier, used: quota.used, limit: quota.limit });

    const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, maxRetries: 1 });
    const { readable, writable } = new TransformStream<Uint8Array, Uint8Array>();
    const writer = writable.getWriter();
    const encoder = new TextEncoder();
    const send = (event: string, data: unknown) =>
      writer.write(encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)).catch(() => undefined);

    ctx.waitUntil(
      (async () => {
        try {
          const stream = client.beta.messages.stream(buildParams(config, turn.messages));
          for await (const event of stream) {
            if (event.type === "content_block_start" && event.content_block.type === "tool_use") {
              await send("tool", { name: event.content_block.name });
            } else if (event.type === "content_block_delta" && event.delta.type === "text_delta") {
              await send("text", { text: event.delta.text });
            }
          }
          const message = await stream.finalMessage();
          await send("done", { ...donePayload(message), tier, quota: { used: quota.used, limit: quota.limit } });
        } catch (error) {
          const payload = errorPayload(error);
          console.log(`turn error ${payload.code}${error instanceof Anthropic.APIError ? ` ${error.status}` : ""}`);
          await send("error", payload);
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
