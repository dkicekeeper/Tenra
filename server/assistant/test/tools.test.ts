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

  it("avoid keywords strict mode does not support", () => {
    const serialized = JSON.stringify(TOOLS.filter((t) => t.strict).map((t) => t.input_schema));
    for (const keyword of ["minimum", "maximum", "minLength", "maxLength", "multipleOf", "minItems", "maxItems"]) {
      expect(serialized).not.toContain(`"${keyword}"`);
    }
  });
});
