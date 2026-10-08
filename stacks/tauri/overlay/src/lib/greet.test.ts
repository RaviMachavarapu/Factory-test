import { describe, expect, it } from "vitest";
import { greeting } from "./greet";

describe("greeting", () => {
  it("greets by name", () => {
    expect(greeting("Ada")).toBe("Hello, Ada!");
  });
  it("falls back when the name is blank", () => {
    expect(greeting("   ")).toBe("Hello, friend!");
  });
});
