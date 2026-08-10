/**
 * /nlm — NotebookLM (Gemini Notebook) for pi.
 *
 * Shipped in the install bundle. Surfaces the NotebookLM research backend:
 *
 *   /nlm                        interactive menu (select/change notebook,
 *                               auth, query, sources, doctor, Docker MCP
 *                               install/remove)
 *   /nlm select                 pick the current notebook (remembered)
 *   /nlm current                show the selected notebook
 *   /nlm <nlm args>             passthrough to the `nlm` CLI
 *   /nlm setup                  install the NotebookLM MCP server in the
 *                               Docker MCP gateway (wrapper around
 *                               ~/.pi/scripts/setup-notebooklm.sh)
 *   /nlm remove                 remove it again
 *
 * The extension is the wrapper that installs the NotebookLM MCP server into
 * the Docker MCP gateway: it shells out to the setup script shipped with the
 * bundle, so the backend can be installed or torn down from inside pi without
 * a reinstall.
 */

import type {
	ExtensionAPI,
	ExtensionCommandContext,
} from "@earendil-works/pi-coding-agent";
import { Box, Text } from "@earendil-works/pi-tui";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

interface NlmOutput {
	command: string;
	output: string;
	exitCode: number;
}

/** The notebook currently selected via /nlm, persisted to disk. */
interface CurrentNotebook {
	notebookId: string;
	notebookTitle: string;
}

/** One entry from `nlm notebook list --json`. */
interface NotebookListItem {
	id: string;
	title: string;
	sourceCount: number;
}

const MAX_COLLAPSED_LINES = 25;
const SETUP_SCRIPT = `${process.env.HOME}/.pi/scripts/setup-notebooklm.sh`;

const MENU = [
	"🔑 Auth status / login",
	"📚 List notebooks",
	"💬 Ask a question",
	"➕ Add a source",
	"⚙️ Install MCP server in Docker",
	"🗑️ Remove MCP server from Docker",
	"🩺 Doctor",
	"▸ Run any nlm command",
] as const;

/** Single-quote a value for embedding in a `bash -c` string. */
function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'\\''`)}'`;
}

/** Does the command ask the notebook a question (`nlm notebook query …`)? */
function isNotebookQuery(cmd: string): boolean {
	return /^notebook\s+query\b/.test(cmd.trim());
}

/**
 * Extract the answer text from `nlm notebook query … --json` stdout. Unwraps
 * a `value` object if the formatter wrapped the result, then takes `answer`
 * (falling back to `response`). Returns `undefined` on any parse failure or
 * when no answer string is present — callers fall back to the raw output.
 */
function extractAnswer(stdout: string): string | undefined {
	let parsed: unknown;
	try {
		parsed = JSON.parse(stdout);
	} catch {
		return undefined;
	}
	if (typeof parsed === "object" && parsed !== null && !Array.isArray(parsed)) {
		const data = parsed as Record<string, unknown>;
		const unwrapped =
			typeof data.value === "object" && data.value !== null
				? (data.value as Record<string, unknown>)
				: data;
		if (typeof unwrapped.answer === "string") return unwrapped.answer;
		if (typeof unwrapped.response === "string") return unwrapped.response;
	}
	return undefined;
}

/** Build `KEY='value'` env assignments for the setup script, from the session env. */
function setupEnvAssignments(): string {
	const keys = [
		"NOTEBOOKLM_ACCOUNT",
		"NOTEBOOKLM_MCP_PORT",
		"NOTEBOOKLM_MCP_TOKEN",
		"NOTEBOOKLM_MCP_PROFILE",
	];
	const parts: string[] = [];
	for (const key of keys) {
		const value = process.env[key];
		if (value) parts.push(`${key}=${shellQuote(value)}`);
	}
	return parts.length > 0 ? `${parts.join(" ")} ` : "";
}

/**
 * PATH prefix so `nlm` resolves even when ~/.local/bin is not yet on the
 * inherited PATH (uv/pipx/pip --user all install nlm there).
 */
function nlmEnvPrefix(): string {
	return `export PATH=${shellQuote(`${process.env.HOME}/.local/bin`)}:$PATH; `;
}

/** Directory the setup script uses for its generated config (mirrors CONFIG_DIR). */
function configDir(): string {
	return `${process.env.XDG_CONFIG_HOME ?? `${process.env.HOME}/.config`}/install-pi-dev`;
}

/** Where the selected notebook is persisted. */
function statePath(): string {
	return join(configDir(), "notebooklm-state.json");
}

/** Load the selected notebook; missing/corrupt state means "none selected". */
async function loadCurrentNotebook(): Promise<CurrentNotebook | undefined> {
	try {
		const parsed = JSON.parse(await readFile(statePath(), "utf8")) as {
			notebookId?: unknown;
			notebookTitle?: unknown;
		};
		if (
			typeof parsed.notebookId === "string" &&
			typeof parsed.notebookTitle === "string"
		) {
			return {
				notebookId: parsed.notebookId,
				notebookTitle: parsed.notebookTitle,
			};
		}
	} catch {
		// no state file yet (or it is corrupt) — treat as "none selected"
	}
	return undefined;
}

/** Persist (or clear, when `undefined`) the selected notebook. Best-effort. */
async function saveCurrentNotebook(
	current: CurrentNotebook | undefined,
): Promise<void> {
	const file = statePath();
	try {
		if (!current) {
			await rm(file, { force: true });
			return;
		}
		await mkdir(configDir(), { recursive: true });
		await writeFile(file, `${JSON.stringify(current, null, 2)}\n`, {
			mode: 0o600,
		});
	} catch {
		// persistence is best-effort — the session still works without it
	}
}

/**
 * Fetch the user's notebooks via `nlm notebook list --json`. Returns the
 * parsed list, or `undefined` (with a notification) when the CLI is missing,
 * listing fails, or the output cannot be parsed.
 */
async function listNotebooks(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
): Promise<NotebookListItem[] | undefined> {
	const result = await pi.exec(
		"bash",
		["-c", `${nlmEnvPrefix()}nlm notebook list --json`],
		{ signal: ctx.signal },
	);
	if (result.code !== 0) {
		const available = await pi.exec(
			"bash",
			["-c", `${nlmEnvPrefix()}command -v nlm >/dev/null 2>&1`],
			{ signal: ctx.signal },
		);
		if (available.code !== 0) {
			ctx.ui.notify(
				"`nlm` is not installed. Run /nlm → “Install MCP server in Docker” (or `sh ~/.pi/scripts/setup-notebooklm.sh`) to set up the NotebookLM backend.",
				"warning",
			);
		} else {
			ctx.ui.notify(
				`Could not list notebooks: ${(result.stderr || result.stdout).slice(0, 300)}`,
				"error",
			);
		}
		return undefined;
	}
	try {
		const parsed = JSON.parse(result.stdout) as Array<{
			id?: unknown;
			title?: unknown;
			source_count?: unknown;
		}>;
		return parsed
			.filter(
				(notebook) =>
					typeof notebook.id === "string" && typeof notebook.title === "string",
			)
			.map((notebook) => ({
				id: notebook.id as string,
				title: notebook.title as string,
				sourceCount:
					typeof notebook.source_count === "number" ? notebook.source_count : 0,
			}));
	} catch {
		ctx.ui.notify(
			"Could not parse `nlm notebook list --json` output.",
			"error",
		);
		return undefined;
	}
}

async function runNlm(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
	cmd: string,
): Promise<number> {
	const available = await pi.exec(
		"bash",
		["-c", `${nlmEnvPrefix()}command -v nlm >/dev/null 2>&1`],
		{ signal: ctx.signal },
	);
	if (available.code !== 0) {
		ctx.ui.notify(
			"`nlm` is not installed. Run /nlm → “Install MCP server in Docker” (or `sh ~/.pi/scripts/setup-notebooklm.sh`) to set up the NotebookLM backend.",
			"warning",
		);
		return 127;
	}
	if (isNotebookQuery(cmd)) {
		ctx.ui.notify("Asking your sources…", "info");
	}
	const result = await pi.exec("bash", ["-c", `${nlmEnvPrefix()}nlm ${cmd}`], {
		signal: ctx.signal,
	});
	let output = result.stdout || result.stderr;
	if (result.code === 0 && isNotebookQuery(cmd)) {
		// Surface only the answer — drop conversation_id, sources_used,
		// citations, and the (large) references payload.
		output = extractAnswer(result.stdout) ?? output;
	}
	pi.appendEntry<NlmOutput>("nlm-output", {
		command: cmd,
		output,
		exitCode: result.code,
	});
	if (result.code !== 0 && result.stderr) {
		ctx.ui.notify(
			`nlm exited ${result.code}: ${result.stderr.slice(0, 300)}`,
			"error",
		);
	}
	return result.code;
}

async function runSetup(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
	remove: boolean,
): Promise<void> {
	const scriptCheck = await pi.exec(
		"bash",
		["-c", `test -f ${shellQuote(SETUP_SCRIPT)}`],
		{ signal: ctx.signal },
	);
	if (scriptCheck.code !== 0) {
		ctx.ui.notify(
			`Setup script not found at ${SETUP_SCRIPT} — reinstall the bundle to refresh it.`,
			"error",
		);
		return;
	}
	const action = remove
		? "Removing NotebookLM MCP server from Docker"
		: "Installing NotebookLM MCP server in Docker";
	ctx.ui.notify(`${action}…`, "info");
	const command = remove
		? `sh ${shellQuote(SETUP_SCRIPT)} --remove`
		: `${setupEnvAssignments()}sh ${shellQuote(SETUP_SCRIPT)}`;
	const result = await pi.exec("bash", ["-c", command], { signal: ctx.signal });
	pi.appendEntry<NlmOutput>("nlm-output", {
		command: remove ? "setup-notebooklm.sh --remove" : "setup-notebooklm.sh",
		output: result.stdout || result.stderr,
		exitCode: result.code,
	});
	if (result.code !== 0) {
		ctx.ui.notify(
			`NotebookLM setup exited ${result.code}: ${(result.stderr || result.stdout).slice(0, 300)}`,
			"error",
		);
	} else if (remove) {
		ctx.ui.notify(
			"NotebookLM MCP server removed from Docker (nlm CLI + auth kept).",
			"info",
		);
	} else {
		ctx.ui.notify(
			"NotebookLM MCP server installed in Docker — `docker mcp tools ls | grep -i notebook`.",
			"info",
		);
	}
}

const CLEAR_SELECTION = "❌ Clear selection";

/**
 * Pick the current notebook from the user's real list. Persists the choice
 * (or clears it). Safe to call from the menu, from the auto-open on bare
 * /nlm, or from `/nlm select` — failures only notify, never throw.
 */
async function selectNotebook(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
): Promise<void> {
	const current = await loadCurrentNotebook();
	const notebooks = await listNotebooks(pi, ctx);
	if (!notebooks) return;
	if (notebooks.length === 0) {
		ctx.ui.notify(
			"No notebooks found — create one in NotebookLM first, then select it here.",
			"info",
		);
		return;
	}
	const options = notebooks.map(
		(notebook) =>
			`${notebook.id === current?.notebookId ? "● " : ""}${notebook.title}  (${notebook.sourceCount} source${notebook.sourceCount === 1 ? "" : "s"})`,
	);
	if (current) options.push(CLEAR_SELECTION);
	const choice = await ctx.ui.select("NotebookLM — select a notebook", options);
	if (!choice) return; // cancelled
	if (choice === CLEAR_SELECTION) {
		await saveCurrentNotebook(undefined);
		ctx.ui.notify("Current notebook cleared.", "info");
		return;
	}
	const picked = notebooks[options.indexOf(choice)];
	if (!picked) return;
	await saveCurrentNotebook({
		notebookId: picked.id,
		notebookTitle: picked.title,
	});
	ctx.ui.notify(`Current notebook: ${picked.title}`, "info");
}

/**
 * Resolve the notebook target for ask/add flows: when one is selected, confirm
 * it first (fall back to manual entry when declined); otherwise ask outright.
 */
async function resolveNotebook(
	ctx: ExtensionCommandContext,
	current: CurrentNotebook | undefined,
	confirmTitle: string,
): Promise<string | undefined> {
	if (current) {
		const use = await ctx.ui.confirm(
			confirmTitle,
			`Use current notebook “${current.notebookTitle}”?`,
		);
		if (use) return current.notebookId;
	}
	return ctx.ui.input("Notebook", "notebook id or name");
}

async function showMenu(
	pi: ExtensionAPI,
	ctx: ExtensionCommandContext,
	autoOpenPicker: boolean,
): Promise<void> {
	if (autoOpenPicker && !(await loadCurrentNotebook())) {
		// Bare /nlm with nothing selected: open the picker first. A cancelled
		// or failed picker must not trap the user — fall through to the menu.
		await selectNotebook(pi, ctx);
	}
	const current = await loadCurrentNotebook();
	const menu = [
		current
			? `📓 Change notebook: ${current.notebookTitle}`
			: "📓 Select notebook",
		...MENU,
	];
	const choice = await ctx.ui.select("NotebookLM — choose an option", menu);
	if (!choice) return;

	if (choice.startsWith("📓")) {
		await selectNotebook(pi, ctx);
		return;
	}

	switch (choice) {
		case "🔑 Auth status / login": {
			const code = await runNlm(pi, ctx, "login --check");
			if (code !== 0) {
				const login = await ctx.ui.confirm(
					"NotebookLM login",
					"Not authenticated (or the session expired). Open your browser to sign in to the Google account that holds your notebooks?",
				);
				if (login) await runNlm(pi, ctx, "login");
			}
			break;
		}
		case "📚 List notebooks":
			await runNlm(pi, ctx, "notebook list");
			break;
		case "💬 Ask a question": {
			const notebook = await resolveNotebook(ctx, current, "Ask a question");
			if (!notebook) break;
			const question = await ctx.ui.input(
				"Question",
				"what do you want to ask your sources?",
			);
			if (!question) break;
			await runNlm(
				pi,
				ctx,
				`notebook query ${shellQuote(notebook)} ${shellQuote(question)} --json`,
			);
			break;
		}
		case "➕ Add a source": {
			const notebook = await resolveNotebook(ctx, current, "Add a source");
			if (!notebook) break;
			const url = await ctx.ui.input("Source URL", "https://…");
			if (!url) break;
			await runNlm(
				pi,
				ctx,
				`source add ${shellQuote(notebook)} --url ${shellQuote(url)} --wait`,
			);
			break;
		}
		case "⚙️ Install MCP server in Docker":
			await runSetup(pi, ctx, false);
			break;
		case "🗑️ Remove MCP server from Docker": {
			const remove = await ctx.ui.confirm(
				"Remove NotebookLM MCP server",
				"Remove the `notebooklm` server from the Docker MCP gateway and stop its service? (The nlm CLI and your auth stay.)",
			);
			if (remove) await runSetup(pi, ctx, true);
			break;
		}
		case "🩺 Doctor":
			await runNlm(pi, ctx, "doctor");
			break;
		case "▸ Run any nlm command": {
			const cmd = await ctx.ui.input("nlm command", "e.g. notebook list");
			if (cmd) await runNlm(pi, ctx, cmd);
			break;
		}
	}
}

export default function nlmExtension(pi: ExtensionAPI) {
	pi.registerEntryRenderer<NlmOutput>(
		"nlm-output",
		(entry, { expanded }, theme) => {
			const { command, output, exitCode } = entry.data ?? {
				command: "",
				output: "",
				exitCode: 0,
			};
			const ok = exitCode === 0;
			const lines = output.replace(/\r\n/g, "\n").split("\n");
			const shown = expanded ? lines : lines.slice(0, MAX_COLLAPSED_LINES);

			const box = new Box(1, 1, (text) => theme.bg("customMessageBg", text));
			box.addChild(
				new Text(
					theme.fg(
						ok ? "accent" : "error",
						`[nlm] $ ${command}${ok ? "" : `  (exit ${exitCode})`}`,
					),
					0,
					0,
				),
			);
			for (const line of shown) {
				box.addChild(new Text(theme.fg("text", line), 0, 0));
			}
			if (!expanded && lines.length > MAX_COLLAPSED_LINES) {
				box.addChild(
					new Text(
						theme.fg(
							"dim",
							`… ${lines.length - MAX_COLLAPSED_LINES} more lines (expand to show)`,
						),
						0,
						0,
					),
				);
			}
			return box;
		},
	);

	pi.registerCommand("nlm", {
		description:
			"NotebookLM (Gemini Notebook): /nlm for the menu (select/change notebook, auth, query, sources, doctor, Docker MCP install/remove), /nlm select to pick the current notebook, /nlm <nlm args> to run the CLI directly",
		getArgumentCompletions: (prefix) => {
			const commands = [
				"select",
				"current",
				"notebook list",
				"notebook query",
				"notebook select",
				"source add",
				"cross query",
				"login --check",
				"setup",
				"remove",
				"doctor",
				"--help",
			];
			const filtered = commands.filter((c) => c.startsWith(prefix));
			return filtered.length > 0
				? filtered.map((s) => ({ value: s, label: s }))
				: null;
		},
		handler: async (args, ctx) => {
			const cmd = args.trim();
			if (!cmd) {
				await showMenu(pi, ctx, true);
				return;
			}
			if (cmd === "setup" || cmd === "install") {
				await runSetup(pi, ctx, false);
				return;
			}
			if (cmd === "remove" || cmd === "uninstall") {
				await runSetup(pi, ctx, true);
				return;
			}
			if (cmd === "select" || cmd === "notebook select") {
				await selectNotebook(pi, ctx);
				return;
			}
			if (cmd === "current" || cmd === "notebook current") {
				const current = await loadCurrentNotebook();
				ctx.ui.notify(
					current
						? `Current notebook: ${current.notebookTitle} (${current.notebookId})`
						: "No notebook selected — run /nlm → “Select notebook” to pick one.",
					"info",
				);
				return;
			}
			await runNlm(pi, ctx, cmd);
		},
	});
}
