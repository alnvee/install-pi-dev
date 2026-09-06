/**
 * herdr-handoff.ts — deterministic worker→main artifact handoff (prototype).
 *
 * Companion to herdr-agent-state.ts. Do NOT edit herdr-agent-state.ts: herdr
 * refreshes it from its own release and overwrites local changes. This file is
 * ours; it ships with the install bundle via repo .pi/agent/extensions/.
 *
 * Roles — one file, both sides of a herdr orchestration:
 *
 *  Worker side: on `agent_settled` — the runtime event that fires only when a
 *  turn is fully done (no retry, compaction, or queued continuation will run) —
 *  commit the artifact the worker wrote to /tmp/herdr/<HERDR_PANE_ID>/out.md.tmp
 *  → out.md, and write out.md.done carrying a strictly increasing seq.
 *  Completion is decided by the runtime event, never by trusting the LLM to
 *  write a marker last.
 *
 *  Main side: registers the `herdr_worker_result` tool — block until the target
 *  pane's artifact seq is newer than at call time (or a caller-supplied
 *  baseline), then return the committed output, bounded. Replaces bash
 *  sleep-polling and terminal-scrollback reads.
 *
 * Worker task contract (paste into the worker prompt):
 *   Write your result to /tmp/herdr/<pane-id>/out.md.tmp
 *   (it is committed to out.md automatically when your turn settles — do not
 *   write out.md or out.md.done yourself)
 *
 * Known ceilings (ponytail):
 *  - The wait uses 250ms polling rather than fs events; that affects latency,
 *    not correctness — the seq comparison is the deterministic gate.
 *  - Single artifact per pane. Use a FRESH pane per task (baseline seq then
 *    starts at 0 and the first commit satisfies the wait). Reusing a pane
 *    across tasks requires passing baselineSeq explicitly.
 *  - Name resolution goes over the herdr socket (HERDR_SOCKET_PATH) when
 *    available, so it works from ANY herdr pane; the herdr CLI fallback only
 *    applies outside a herdr pane. The CLI is blocked inside spawned panes
 *    ("nested herdr disabled") — the socket is not.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "@earendil-works/pi-ai";
import {
	existsSync,
	mkdirSync,
	readFileSync,
	renameSync,
	rmSync,
	statSync,
	writeFileSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import net from "node:net";
import { join } from "node:path";

const BASE_DIR = "/tmp/herdr";

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function donePath(pane: string): string {
	return join(BASE_DIR, pane, "out.md.done");
}
function outPath(pane: string): string {
	return join(BASE_DIR, pane, "out.md");
}
function tmpPath(pane: string): string {
	return join(BASE_DIR, pane, "out.md.tmp");
}

function readDoneMeta(pane: string): {
	seq: number;
	status?: string;
	bytes?: number;
	session?: string | null;
	at?: number;
} | null {
	try {
		return JSON.parse(readFileSync(donePath(pane), "utf8"));
	} catch {
		return null;
	}
}

function readDoneSeq(pane: string): number {
	return readDoneMeta(pane)?.seq ?? 0;
}

/**
 * Minimal JSON-RPC request over herdr's unix socket — the same protocol the
 * herdr-agent-state extension uses to report state. Works from any herdr pane
 * (the "nested herdr disabled" guard applies to the herdr CLI, not the socket).
 * Returns the response `result`, or null on error/timeout.
 */
function socketRequest(
	method: string,
	params: Record<string, unknown>,
	timeoutMs = 2000,
): Promise<any | null> {
	const sockPath = process.env.HERDR_SOCKET_PATH;
	if (!sockPath) {
		return Promise.resolve(null);
	}
	return new Promise((resolve) => {
		let done = false;
		const finish = (v: any) => {
			if (done) return;
			done = true;
			clearTimeout(timer);
			sock.destroy();
			resolve(v);
		};
		const id = `hh:${Date.now()}:${Math.random().toString(36).slice(2)}`;
		let buf = "";
		const timer = setTimeout(() => finish(null), timeoutMs);
		const sock = net.createConnection(sockPath);
		sock.on("error", () => finish(null));
		sock.on("connect", () =>
			sock.write(JSON.stringify({ id, method, params }) + "\n"),
		);
		sock.on("data", (chunk) => {
			buf += chunk.toString();
			const lines = buf.split("\n");
			buf = lines.pop() ?? "";
			for (const line of lines) {
				if (!line.trim()) continue;
				try {
					const msg = JSON.parse(line);
					if (msg.id === id) {
						finish(msg.result ?? null);
						return;
					}
				} catch {
					// partial line; keep buffering
				}
			}
		});
	});
}

/**
 * Resolve an agent name to its herdr pane id ("w1:p3"); pane ids pass through.
 * Socket first (any herdr pane), herdr CLI as fallback (outside a herdr pane).
 */
async function resolvePane(target: string): Promise<string | null> {
	if (target.includes(":")) {
		return target;
	}
	const viaSocket = await socketRequest("agent.list", {});
	const found = (viaSocket?.agents ?? []).find((a: any) => a.name === target);
	if (found?.pane_id) {
		return found.pane_id;
	}
	try {
		const out = execFileSync("herdr", ["agent", "list"], { encoding: "utf8" });
		const agent = (JSON.parse(out)?.result?.agents ?? []).find(
			(a: any) => a.name === target,
		);
		return agent?.pane_id ?? null;
	} catch {
		return null;
	}
}

export default function (pi: ExtensionAPI) {
	// --- worker side: commit the artifact on the deterministic settle event ---
	const paneId = process.env.HERDR_PANE_ID;
	if (paneId) {
		let seq = readDoneSeq(paneId);
		pi.on("agent_start", () => {
			// A stale tmp can only survive a turn that crashed before settling;
			// remove it so the next settle never commits another turn's bytes.
			try {
				rmSync(tmpPath(paneId), { force: true });
			} catch {
				// ignore — settle will see no-artifact instead of stale content
			}
		});
		pi.on("agent_settled", (_event, ctx: any) => {
			try {
				mkdirSync(join(BASE_DIR, paneId), { recursive: true });
				const tmp = tmpPath(paneId);
				const hasTmp = existsSync(tmp);
				const status = hasTmp ? "committed" : "no-artifact";
				const bytes = hasTmp ? statSync(tmp).size : 0;
				if (status === "committed") {
					renameSync(tmp, outPath(paneId));
				}
				seq += 1;
				writeFileSync(
					donePath(paneId),
					JSON.stringify({
						seq,
						status,
						bytes,
						session: ctx?.sessionManager?.getSessionFile?.() ?? null,
						at: Date.now(),
					}) + "\n",
				);
			} catch {
				// Leave the artifact for the next settle to retry.
			}
		});
	}

	// --- main side: deterministic wait + bounded read as one tool call ---------
	pi.registerTool({
		name: "herdr_worker_result",
		label: "herdr worker result",
		description:
			"Wait until a herdr worker agent's turn has settled and its artifact " +
			"(/tmp/herdr/<pane-id>/out.md) is committed — the commit is performed by " +
			"the agent_settled extension hook, so a returned artifact is complete, " +
			"never a mid-turn write — then return the output, bounded. " +
			"Call right after spawning the worker. Args: target = agent name (resolved " +
			"over the herdr socket) or pane id; timeoutMs (default 120000); " +
			"baselineSeq = wait for a commit strictly newer than this seq " +
			"(default 0: returns the existing commit on a fresh pane; pass the prior " +
			"seq when reusing a pane across tasks); " +
			"maxChars = content cap (default 20000).",
		promptSnippet:
			"herdr_worker_result — read a spawned herdr worker's committed result.",
		promptGuidelines: [
			"After `herdr agent start`, call herdr_worker_result with the agent name to collect its output instead of bash-polling or reading its terminal.",
			"If the result is no-artifact or a timeout, use the herdr failure ladder (explain → prompt → read) before retrying.",
		],
		parameters: Type.Object({
			target: Type.String({
				description: "Agent name or herdr pane id (e.g. wK:p3 or worker).",
			}),
			timeoutMs: Type.Optional(
				Type.Number({ description: "Wait ceiling in ms. Default 120000." }),
			),
			baselineSeq: Type.Optional(
				Type.Number({
					description:
						"Wait for a commit with seq > this. Default: seq at call time.",
				}),
			),
			maxChars: Type.Optional(
				Type.Number({ description: "Content cap. Default 20000." }),
			),
		}) as any,

		async execute(_toolCallId, params: any, signal?: AbortSignal) {
			const target = String(params?.target ?? "").trim();
			if (!target) {
				return {
					content: [
						{
							type: "text",
							text:
								"Error: herdr_worker_result requires a target (agent name or pane id).",
						},
					],
					details: { ok: false },
				};
			}
			const pane = await resolvePane(target);
			if (!pane) {
				return {
					content: [
						{
							type: "text",
							text: `Error: no herdr agent or pane matches "${target}". Is it running?`,
						},
					],
					details: { ok: false },
				};
			}

			// Default baseline 0: a fresh pane's first commit (seq 1) satisfies the
			// wait immediately. Reusing a pane across tasks → pass baselineSeq.
			const baseline = Number(params?.baselineSeq ?? 0);
			const timeoutMs = Number(params?.timeoutMs ?? 120000);
			const maxChars = Number(params?.maxChars ?? 20000);
			const deadline = Date.now() + timeoutMs;

			// Wait for a committed revision strictly newer than the baseline.
			while (Date.now() < deadline && !signal?.aborted) {
				const meta = readDoneMeta(pane);
				if (meta && meta.seq > baseline) {
					break;
				}
				if (signal?.aborted) {
					break;
				}
				await sleep(250);
			}

			const meta = readDoneMeta(pane);
			const newer = meta && meta.seq > baseline;
			const timedOut = !newer;

			if (meta?.status === "no-artifact" && meta.seq > baseline) {
				return {
					content: [
						{
							type: "text",
							text: `Worker on ${pane} settled but wrote no artifact (no out.md.tmp found at commit time). Use the herdr failure ladder: agent explain → prompt → read.`,
						},
					],
					details: {
						ok: false,
						pane,
						seq: meta.seq,
						status: meta.status,
						session: meta.session ?? null,
					},
				};
			}

			let text = "";
			let truncated = false;
			let bytes = 0;
			try {
				const raw = readFileSync(outPath(pane), "utf8");
				bytes = raw.length;
				if (bytes > maxChars) {
					text =
						raw.slice(0, maxChars) +
						`\n… [truncated at ${maxChars} chars; full artifact: ${outPath(pane)}]`;
					truncated = true;
				} else {
					text = raw;
				}
			} catch {
				text = "";
			}

			if (!text && timedOut) {
				return {
					content: [
						{
							type: "text",
							text: `No new commit on ${pane} within ${timeoutMs}ms (baseline seq ${baseline}). Worker may still be working or blocked — use agent explain.`,
						},
					],
					details: { ok: false, pane, baseline, timedOut: true },
				};
			}

			return {
				content: [
					{
						type: "text",
						text: `Worker artifact (${pane}, seq ${meta?.seq ?? "?"}, ${bytes} bytes${truncated ? ", truncated" : ""}):\n\n${text}`,
					},
				],
				details: {
					ok: true,
					pane,
					seq: meta?.seq ?? null,
					status: meta?.status ?? null,
					session: meta?.session ?? null,
					bytes,
					truncated,
					timedOut,
				},
			};
		},
	});
}
