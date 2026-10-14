import { describe, expect, it } from "vitest";
import { TOOLS } from "../src/tools";

type Node = Record<string, unknown>;

// Walks every object schema reachable from a tool's input_schema.
function objects(schema: unknown, out: Node[] = []): Node[] {
  if (Array.isArray(schema)) schema.forEach((s) => objects(s, out));
  else if (schema && typeof schema === "object") {
    const node = schema as Node;
    if (node.type === "object") out.push(node);
    Object.values(node).forEach((v) => objects(v, out));
  }
  return out;
}

describe("tool schemas", () => {
  it("have unique names", () => {
    const names = TOOLS.map((t) => t.name);
    expect(new Set(names).size).toBe(names.length);
  });

  it("close every object", () => {
    for (const tool of TOOLS) {
      for (const node of objects(tool.input_schema)) {
        expect(node.additionalProperties, `${tool.name}`).toBe(false);
      }
    }
  });

  it("list every property as required in strict tools", () => {
    for (const tool of TOOLS.filter((t) => t.strict)) {
      for (const node of objects(tool.input_schema)) {
        const properties = Object.keys((node.properties as Node) ?? {});
        expect(new Set(node.required as string[]), `${tool.name}`).toEqual(new Set(properties));
      }
    }
  });

  // The API refuses every request whose strict tools have more than 16 parameters with a union
  // type ("Schemas contains too many parameters with union types"), so Ten stops answering.
  it("keep strict union-typed parameters within the API's limit", () => {
    const unions = (schema: unknown): number => {
      if (Array.isArray(schema)) return schema.reduce((sum: number, s) => sum + unions(s), 0);
      if (!schema || typeof schema !== "object") return 0;
      const node = schema as Node;
      const own = Array.isArray(node.anyOf) || Array.isArray(node.type) ? 1 : 0;
      return own + Object.values(node).reduce((sum: number, v) => sum + unions(v), 0);
    };
    const count = TOOLS.filter((t) => t.strict).reduce((sum, t) => sum + unions(t.input_schema), 0);
    expect(count).toBeLessThanOrEqual(16);
  });

  it("avoid keywords strict mode does not support", () => {
    const serialized = JSON.stringify(TOOLS.filter((t) => t.strict).map((t) => t.input_schema));
    for (const keyword of ["minimum", "maximum", "minLength", "maxLength", "multipleOf", "minItems", "maxItems"]) {
      expect(serialized).not.toContain(`"${keyword}"`);
    }
  });
});
