// In-memory stand-in for the KV namespace: enough for get/put with TTLs ignored.
export class MemoryKV {
  readonly store = new Map<string, string>();
  async get(key: string): Promise<string | null> {
    return this.store.get(key) ?? null;
  }
  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }
}

export const userTurn = (text: string) => ({ role: "user" as const, content: [{ type: "text" as const, text }] });

export const body = (messages: unknown[], protocol = 1) => JSON.stringify({ protocol, messages });
