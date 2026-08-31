import assert from "node:assert/strict";
import test from "node:test";
import { SUBAGENT_PROFILES } from "./src/model-profile.ts";

test("medium, high and low profiles are exposed", () => {
  assert.deepEqual(SUBAGENT_PROFILES, ["high", "low", "medium"]);
});
