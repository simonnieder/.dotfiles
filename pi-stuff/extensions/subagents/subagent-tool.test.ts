import assert from "node:assert/strict";
import test from "node:test";
import { Value } from "typebox/value";
import {
  SUBAGENT_HARNESS_SCHEMA,
  SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS,
  SUBAGENT_SPAWN_PROMPT_GUIDELINES,
  SUBAGENT_SPAWN_PROMPT_SNIPPET,
  SUBAGENT_SPAWN_TOOL_DESCRIPTION,
} from "./src/prompt.ts";

test("the public harness schema only accepts pi", () => {
  assert.equal(Value.Check(SUBAGENT_HARNESS_SCHEMA, "pi"), true);
  assert.equal(Value.Check(SUBAGENT_HARNESS_SCHEMA, "claude"), false);
  assert.equal(Value.Check(SUBAGENT_HARNESS_SCHEMA, "codex"), false);
});

test("model-facing subagent metadata only advertises pi", () => {
  const metadata = [
    SUBAGENT_SPAWN_TOOL_DESCRIPTION,
    SUBAGENT_SPAWN_PROMPT_SNIPPET,
    ...SUBAGENT_SPAWN_PROMPT_GUIDELINES,
    ...Object.values(SUBAGENT_SPAWN_PARAMETER_DESCRIPTIONS),
  ].join("\n");

  assert.doesNotMatch(metadata, /claude/i);
});
