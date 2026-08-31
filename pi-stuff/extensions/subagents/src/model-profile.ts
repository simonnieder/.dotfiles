import { readdirSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import {
  REASONING_EFFORTS,
  type BackendName,
  type ReasoningEffort,
} from "./domain.ts";

export const PROFILE_DIRECTORY = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "..",
  "profiles",
);

type SubagentProfileDefinition = {
  readonly name: string;
  readonly description: string;
  /** Full provider/model reference for the pi backend. */
  readonly model: string;
  /** Native model slug for the Codex backend, when supported. */
  readonly codexModel?: string;
  readonly reasoningEffort: ReasoningEffort;
};

export type SubagentProfile = string;

export interface SubagentProfileSelection {
  readonly model?: string;
  readonly reasoningEffort: ReasoningEffort;
}

function parseFrontmatter(content: string, filePath: string): Record<string, string> {
  if (!content.startsWith("---\n")) {
    throw new Error(`Profile ${filePath} must start with YAML frontmatter.`);
  }
  const end = content.indexOf("\n---", 4);
  if (end === -1) {
    throw new Error(`Profile ${filePath} has unterminated frontmatter.`);
  }

  const frontmatter: Record<string, string> = {};
  for (const line of content.slice(4, end).trim().split("\n")) {
    if (!line.trim()) continue;
    const match = line.match(/^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/);
    if (!match) throw new Error(`Profile ${filePath} has invalid frontmatter line: ${line}`);
    frontmatter[match[1]] = match[2].trim().replace(/^(["']).*\1$/, (value) => value.slice(1, -1));
  }
  return frontmatter;
}

function required(frontmatter: Record<string, string>, key: string, filePath: string): string {
  const value = frontmatter[key]?.trim();
  if (!value) throw new Error(`Profile ${filePath} requires ${key}.`);
  return value;
}

function parseReasoning(value: string, filePath: string): ReasoningEffort {
  if (REASONING_EFFORTS.includes(value as ReasoningEffort)) {
    return value as ReasoningEffort;
  }
  throw new Error(
    `Profile ${filePath} has invalid reasoning ${JSON.stringify(value)}; expected ${REASONING_EFFORTS.join(", ")}.`,
  );
}

function loadProfile(filePath: string): SubagentProfileDefinition {
  const frontmatter = parseFrontmatter(readFileSync(filePath, "utf8"), filePath);
  return {
    name: required(frontmatter, "name", filePath),
    description: required(frontmatter, "description", filePath),
    model: required(frontmatter, "model", filePath),
    codexModel: frontmatter["codex-model"]?.trim() || undefined,
    reasoningEffort: parseReasoning(required(frontmatter, "reasoning", filePath), filePath),
  };
}

function loadProfiles(): Map<string, SubagentProfileDefinition> {
  const files = readdirSync(PROFILE_DIRECTORY)
    .filter((file) => file.endsWith(".md"))
    .sort()
    .map((file) => path.join(PROFILE_DIRECTORY, file));
  if (files.length === 0) throw new Error(`No subagent profiles found in ${PROFILE_DIRECTORY}.`);

  const profiles = new Map<string, SubagentProfileDefinition>();
  for (const filePath of files) {
    const profile = loadProfile(filePath);
    if (profiles.has(profile.name)) {
      throw new Error(`Duplicate subagent profile name ${JSON.stringify(profile.name)}.`);
    }
    profiles.set(profile.name, profile);
  }
  return profiles;
}

const PROFILE_BY_NAME = loadProfiles();

/** Profile names are loaded from profiles/*.md at extension startup. */
export const SUBAGENT_PROFILES = [...PROFILE_BY_NAME.keys()] as readonly string[];

export function describeSubagentProfiles(): string {
  return [...PROFILE_BY_NAME.values()]
    .map((profile) =>
      `"${profile.name}" — ${profile.description} (${profile.model}, ${profile.reasoningEffort} reasoning)`,
    )
    .join("; ");
}

export function selectSubagentProfile(
  profileName: SubagentProfile,
  backend: BackendName,
): SubagentProfileSelection {
  const profile = PROFILE_BY_NAME.get(profileName);
  if (!profile) {
    throw new Error(
      `Unknown subagent profile ${JSON.stringify(profileName)}. Available: ${SUBAGENT_PROFILES.join(", ")}.`,
    );
  }

  const model = backend === "pi"
    ? profile.model
    : backend === "codex"
      ? profile.codexModel
      : undefined;
  return { model, reasoningEffort: profile.reasoningEffort };
}
