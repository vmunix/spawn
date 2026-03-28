import { greet } from "./main.ts";

Deno.test("greet uses the default name", () => {
    if (greet() !== "hello, world") {
        throw new Error("expected default greeting");
    }
});

Deno.test("greet accepts a custom name", () => {
    if (greet("spawn") !== "hello, spawn") {
        throw new Error("expected custom greeting");
    }
});
