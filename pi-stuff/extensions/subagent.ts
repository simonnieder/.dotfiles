import type { ExtensionAPI, ExtensionContext, ExtensionCommandContext } from "@mariozechner/pi-coding-agent";
import { mkdir, readFile, readdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";

type JobStatus = "running" | "completed" | "failed" | "stopped";

type JobMetadata = {
	id: string;
	task: string;
	cwd: string;
	createdAt: number;
	parentSessionFile: string | null;
	pid: number;
	status: JobStatus;
	stdoutPath: string;
	stderrPath: string;
	promptPath: string;
	statusPath: string;
	notifiedAt?: number;
	model?: string;
};

const BASE_DIR = resolve(process.env.HOME ?? ".", ".pi/agent/subagents");
const POLL_MS = 3000;
const TAIL_LINES = 40;

let pollTimer: NodeJS.Timeout | null = null;
let currentSessionFile: string | null = null;

function shQuote(value: string): string {
	return `'${value.replace(/'/g, `'"'"'`)}'`;
}

function modelArg(ctx: ExtensionCommandContext): string | undefined {
	if (!ctx.model) return undefined;
	return `${ctx.model.provider}/${ctx.model.id}`;
}

function buildPrompt(task: string): string {
	return [
		"You are a subagent launched from another Pi session.",
		"Work only on the task below. Be pragmatic and concise.",
		"If you inspect files or make changes, mention the relevant file paths in your final answer.",
		"End with a short report using exactly these headings:",
		"## Outcome",
		"## Files",
		"## Notes",
		"",
		"Task:",
		task,
	].join("\n");
}

async function ensureBaseDir(): Promise<void> {
	await mkdir(BASE_DIR, { recursive: true });
}

function jobDir(id: string): string {
	return join(BASE_DIR, id);
}

function metadataPath(id: string): string {
	return join(jobDir(id), "meta.json");
}

async function readJsonIfExists<T>(path: string): Promise<T | null> {
	try {
		return JSON.parse(await readFile(path, "utf8")) as T;
	} catch {
		return null;
	}
}

async function writeMetadata(meta: JobMetadata): Promise<void> {
	await writeFile(metadataPath(meta.id), JSON.stringify(meta, null, 2) + "\n", "utf8");
}

async function listJobsForSession(sessionFile: string | null): Promise<JobMetadata[]> {
	await ensureBaseDir();
	const entries = await readdir(BASE_DIR, { withFileTypes: true });
	const jobs: JobMetadata[] = [];
	for (const entry of entries) {
		if (!entry.isDirectory()) continue;
		const meta = await readJsonIfExists<JobMetadata>(metadataPath(entry.name));
		if (!meta) continue;
		if ((meta.parentSessionFile ?? null) === (sessionFile ?? null)) {
			jobs.push(meta);
		}
	}
	jobs.sort((a, b) => b.createdAt - a.createdAt);
	return jobs;
}

function processExists(pid: number): boolean {
	try {
		process.kill(pid, 0);
		return true;
	} catch {
		return false;
	}
}

async function refreshJobStatus(meta: JobMetadata): Promise<JobMetadata> {
	const persisted = (await readJsonIfExists<JobMetadata>(metadataPath(meta.id))) ?? meta;
	if (persisted.status !== "running") return persisted;
	const statusFile = await readJsonIfExists<{ status?: JobStatus; exitCode?: number }>(persisted.statusPath);
	if (statusFile?.status && statusFile.status !== "running") {
		persisted.status = statusFile.status;
		await writeMetadata(persisted);
		return persisted;
	}
	if (!processExists(persisted.pid)) {
		persisted.status = "failed";
		await writeMetadata(persisted);
	}
	return persisted;
}

async function tailFile(path: string, lines = TAIL_LINES): Promise<string> {
	try {
		const content = await readFile(path, "utf8");
		return content.split("\n").slice(-lines).join("\n").trim();
	} catch {
		return "";
	}
}

async function startPolling(ctx: ExtensionContext): Promise<void> {
	if (pollTimer) clearInterval(pollTimer);
	if (!ctx.hasUI) return;

	pollTimer = setInterval(async () => {
		try {
			const jobs = await listJobsForSession(currentSessionFile);
			for (const job of jobs) {
				const updated = await refreshJobStatus(job);
				if (updated.status !== "running" && !updated.notifiedAt) {
					updated.notifiedAt = Date.now();
					await writeMetadata(updated);
					ctx.ui.notify(`Subagent ${updated.id.slice(0, 8)} ${updated.status}: ${updated.task}`, updated.status === "completed" ? "success" : "warning");
				}
			}
		} catch (error) {
			console.error("subagent poll failed", error);
		}
	}, POLL_MS);
}

async function stopPolling(): Promise<void> {
	if (pollTimer) {
		clearInterval(pollTimer);
		pollTimer = null;
	}
}

async function createJob(task: string, ctx: ExtensionCommandContext): Promise<JobMetadata> {
	await ensureBaseDir();
	const id = randomUUID();
	const dir = jobDir(id);
	await mkdir(dir, { recursive: true });

	const promptPath = join(dir, "prompt.txt");
	const stdoutPath = join(dir, "stdout.log");
	const stderrPath = join(dir, "stderr.log");
	const statusPath = join(dir, "status.json");
	const runnerPath = join(dir, "runner.sh");
	const model = modelArg(ctx);
	const prompt = buildPrompt(task);
	await writeFile(promptPath, prompt, "utf8");
	await writeFile(statusPath, JSON.stringify({ status: "running", exitCode: null, finishedAt: null }, null, 2) + "\n", "utf8");

	const modelFlag = model ? `--model ${shQuote(model)} ` : "";
	const runner = `#!/usr/bin/env bash
set -u
cd ${shQuote(ctx.cwd)} || exit 1
PROMPT=$(cat ${shQuote(promptPath)})
pi ${modelFlag}-p "$PROMPT" > ${shQuote(stdoutPath)} 2> ${shQuote(stderrPath)}
CODE=$?
STATUS="completed"
if [ "$CODE" -ne 0 ]; then
  STATUS="failed"
fi
cat > ${shQuote(statusPath)} <<JSON
{
  "status": "$STATUS",
  "exitCode": $CODE,
  "finishedAt": $(date +%s)
}
JSON
exit 0
`;
	await writeFile(runnerPath, runner, { encoding: "utf8", mode: 0o755 });

	const child = spawn("bash", [runnerPath], {
		cwd: ctx.cwd,
		detached: true,
		stdio: "ignore",
		env: process.env,
	});
	child.unref();

	const meta: JobMetadata = {
		id,
		task,
		cwd: ctx.cwd,
		createdAt: Date.now(),
		parentSessionFile: ctx.sessionManager.getSessionFile() ?? null,
		pid: child.pid ?? -1,
		status: "running",
		stdoutPath,
		stderrPath,
		promptPath,
		statusPath,
		model,
	};
	await writeMetadata(meta);
	return meta;
}

function formatJobLine(job: JobMetadata): string {
	const age = new Date(job.createdAt).toLocaleString();
	return `${job.id.slice(0, 8)}  ${job.status.padEnd(9)}  ${age}  ${job.task}`;
}

async function showJobs(args: string, ctx: ExtensionCommandContext): Promise<void> {
	const jobs = await listJobsForSession(ctx.sessionManager.getSessionFile() ?? null);
	const id = args.trim();
	if (!id) {
		if (jobs.length === 0) {
			ctx.ui.notify("No subagents for this session", "info");
			return;
		}
		ctx.ui.notify(["Subagents:", ...jobs.map(formatJobLine)].join("\n"), "info");
		return;
	}

	const job = jobs.find((item) => item.id.startsWith(id));
	if (!job) {
		ctx.ui.notify(`No subagent matching ${id}`, "error");
		return;
	}
	const updated = await refreshJobStatus(job);
	const stdout = await tailFile(updated.stdoutPath);
	const stderr = await tailFile(updated.stderrPath);
	const lines = [
		`Subagent ${updated.id}`,
		`Status: ${updated.status}`,
		`Task: ${updated.task}`,
		`CWD: ${updated.cwd}`,
		updated.model ? `Model: ${updated.model}` : undefined,
		stdout ? `\n--- stdout ---\n${stdout}` : undefined,
		stderr ? `\n--- stderr ---\n${stderr}` : undefined,
	].filter(Boolean);
	ctx.ui.notify(lines.join("\n"), updated.status === "completed" ? "success" : "info");
}

async function stopJob(args: string, ctx: ExtensionCommandContext): Promise<void> {
	const id = args.trim();
	if (!id) {
		ctx.ui.notify("Usage: /subagent-stop <id>", "error");
		return;
	}
	const jobs = await listJobsForSession(ctx.sessionManager.getSessionFile() ?? null);
	const job = jobs.find((item) => item.id.startsWith(id));
	if (!job) {
		ctx.ui.notify(`No subagent matching ${id}`, "error");
		return;
	}
	if (job.status !== "running") {
		ctx.ui.notify(`Subagent ${job.id.slice(0, 8)} is already ${job.status}`, "info");
		return;
	}
	try {
		process.kill(job.pid, "SIGTERM");
	} catch {}
	job.status = "stopped";
	await writeFile(job.statusPath, JSON.stringify({ status: "stopped", exitCode: null, finishedAt: Math.floor(Date.now() / 1000) }, null, 2) + "\n", "utf8");
	await writeMetadata(job);
	ctx.ui.notify(`Stopped subagent ${job.id.slice(0, 8)}`, "warning");
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		currentSessionFile = ctx.sessionManager.getSessionFile() ?? null;
		await startPolling(ctx);
	});

	pi.on("session_shutdown", async () => {
		await stopPolling();
	});

	pi.registerCommand("subagent", {
		description: "Launch a background Pi subagent for this session",
		handler: async (args, ctx) => {
			const task = args.trim();
			if (!task) {
				ctx.ui.notify("Usage: /subagent <task>", "error");
				return;
			}
			const job = await createJob(task, ctx);
			ctx.ui.notify(`Started subagent ${job.id.slice(0, 8)} for: ${task}`, "success");
		},
	});

	pi.registerCommand("subagents", {
		description: "List subagents for this session or show one: /subagents [id]",
		handler: async (args, ctx) => {
			await showJobs(args, ctx);
		},
	});

	pi.registerCommand("subagent-stop", {
		description: "Stop a running subagent: /subagent-stop <id>",
		handler: async (args, ctx) => {
			await stopJob(args, ctx);
		},
	});
}
