import { expect, test } from "bun:test";

import { greet } from "./main";

test("greet uses the default name", () => {
    expect(greet()).toBe("hello, world");
});

test("greet accepts a custom name", () => {
    expect(greet("spawn")).toBe("hello, spawn");
});
