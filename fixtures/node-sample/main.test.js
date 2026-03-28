const test = require("node:test");
const assert = require("node:assert/strict");

const { greet } = require("./main");

test("greet uses the default name", () => {
    assert.equal(greet(), "hello, world");
});

test("greet accepts a custom name", () => {
    assert.equal(greet("spawn"), "hello, spawn");
});
