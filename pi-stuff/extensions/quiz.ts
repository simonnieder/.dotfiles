import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
	Container,
	Key,
	matchesKey,
	Text,
	visibleWidth,
	wrapTextWithAnsi,
} from "@earendil-works/pi-tui";
import { Type } from "typebox";

interface QuizOption {
	label: string;
	description?: string;
}

interface QuizDetails {
	question: string;
	options: QuizOption[];
	selectedOptions: number[];
	correctOptions: number[];
	correct: boolean | null;
	explanation?: string;
	cancelled: boolean;
}

const QuizOptionSchema = Type.Object({
	label: Type.String({ description: "Answer text shown to the user" }),
	description: Type.Optional(
		Type.String({ description: "Optional supporting detail shown below the answer" }),
	),
});

const QuizParams = Type.Object({
	question: Type.String({ description: "The multiple-choice question" }),
	options: Type.Array(QuizOptionSchema, {
		description: "Answer choices in display order",
		minItems: 2,
		maxItems: 9,
	}),
	correctOptions: Type.Array(
		Type.Integer({ minimum: 1 }),
		{
			description: "One-based indexes of every correct option; never reveal these before the user answers",
			minItems: 1,
			uniqueItems: true,
		},
	),
	explanation: Type.Optional(
		Type.String({ description: "Concise explanation shown after the user answers" }),
	),
});

function normalizedIndexes(indexes: number[]): number[] {
	return [...new Set(indexes)].sort((a, b) => a - b);
}

function sameIndexes(left: number[], right: number[]): boolean {
	const a = normalizedIndexes(left);
	const b = normalizedIndexes(right);
	return a.length === b.length && a.every((value, index) => value === b[index]);
}

function describeOptions(indexes: number[], options: QuizOption[]): string {
	return indexes
		.map((index) => `${index}. ${options[index - 1]?.label ?? "Unknown option"}`)
		.join(", ");
}

function resultText(details: QuizDetails): string {
	if (details.cancelled) return "User cancelled the quiz without answering.";

	const lines = [
		details.correct ? "Correct." : "Incorrect.",
		`User selected: ${describeOptions(details.selectedOptions, details.options)}`,
		`Correct answers: ${describeOptions(details.correctOptions, details.options)}`,
	];
	if (details.explanation) lines.push(`Explanation: ${details.explanation}`);
	return lines.join("\n");
}

export default function quizExtension(pi: ExtensionAPI) {
	pi.registerTool({
		name: "multiple_choice_quiz",
		label: "Multiple Choice Quiz",
		description:
			"Present one interactive multiple-choice question, allow one or more selections, wait for submission, score the exact selection set, and then display the completed quiz in chat. Use one tool call per question. Vary the position of correct answers across a quiz session; do not repeatedly place the correct answer first.",
		promptSnippet: "Present and score an interactive multiple-choice quiz question",
		promptGuidelines: [
			"Use multiple_choice_quiz when the user explicitly asks to be quizzed or tested with multiple-choice questions.",
			"Call multiple_choice_quiz once per question and do not reveal its correctOptions before the user submits.",
			"Vary correct-answer positions across questions and avoid predictable placement patterns, especially repeatedly using the first option.",
		],
		parameters: QuizParams,
		executionMode: "sequential",
		renderShell: "self",

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const correctOptions = normalizedIndexes(params.correctOptions);
			const invalidCorrectOption = correctOptions.find(
				(index) => index < 1 || index > params.options.length,
			);
			if (invalidCorrectOption !== undefined) {
				throw new Error(
					`correct option ${invalidCorrectOption} is outside the ${params.options.length} available options`,
				);
			}

			const baseDetails: QuizDetails = {
				question: params.question,
				options: params.options,
				selectedOptions: [],
				correctOptions,
				correct: null,
				explanation: params.explanation,
				cancelled: true,
			};

			if (ctx.mode !== "tui") {
				return {
					content: [{ type: "text" as const, text: "Quiz cancelled: interactive TUI is unavailable." }],
					details: baseDetails,
				};
			}

			const selectedOptions = await ctx.ui.custom<number[] | null>((tui, theme, _keybindings, done) => {
				let cursor = 0;
				const selected = new Set<number>();

				function toggle(index: number) {
					if (selected.has(index)) selected.delete(index);
					else selected.add(index);
					tui.requestRender();
				}

				function addWrapped(lines: string[], text: string, width: number, prefix = "") {
					const prefixWidth = visibleWidth(prefix);
					if (prefixWidth >= width) {
						lines.push(...wrapTextWithAnsi(prefix + text, width));
						return;
					}
					const wrapped = wrapTextWithAnsi(text, Math.max(1, width - prefixWidth));
					for (let i = 0; i < wrapped.length; i++) {
						lines.push(`${i === 0 ? prefix : " ".repeat(prefixWidth)}${wrapped[i]}`);
					}
				}

				return {
					render(width: number): string[] {
						const renderWidth = Math.max(1, width);
						const lines: string[] = [];
						lines.push(theme.fg("accent", "─".repeat(renderWidth)));
						addWrapped(lines, theme.fg("accent", theme.bold("Multiple Choice Quiz")), renderWidth, " ");
						lines.push("");
						addWrapped(lines, theme.fg("text", params.question), renderWidth, " ");
						lines.push("");

						for (let index = 0; index < params.options.length; index++) {
							const number = index + 1;
							const isCurrent = cursor === index;
							const isSelected = selected.has(number);
							const marker = isSelected ? "[x]" : "[ ]";
							const pointer = isCurrent ? ">" : " ";
							const color = isCurrent ? "accent" : isSelected ? "success" : "text";
							const prefix = `${pointer} ${marker} ${number}. `;
							addWrapped(lines, theme.fg(color, params.options[index].label), renderWidth, prefix);
							if (params.options[index].description) {
								addWrapped(
									lines,
									theme.fg("muted", params.options[index].description!),
									renderWidth,
									"         ",
								);
							}
						}

						lines.push("");
						const count = selected.size;
						addWrapped(
							lines,
							theme.fg(count > 0 ? "success" : "dim", `${count} selected`),
							renderWidth,
							" ",
						);
						addWrapped(
							lines,
							theme.fg("dim", "↑↓ move • Space toggle • 1–9 toggle • Enter submit • Esc cancel"),
							renderWidth,
							" ",
						);
						lines.push(theme.fg("accent", "─".repeat(renderWidth)));
						return lines;
					},
					invalidate() {},
					handleInput(data: string) {
						if (matchesKey(data, Key.up)) {
							cursor = (cursor - 1 + params.options.length) % params.options.length;
							tui.requestRender();
							return;
						}
						if (matchesKey(data, Key.down)) {
							cursor = (cursor + 1) % params.options.length;
							tui.requestRender();
							return;
						}
						if (matchesKey(data, Key.space)) {
							toggle(cursor + 1);
							return;
						}
						if (/^[1-9]$/.test(data)) {
							const index = Number(data);
							if (index <= params.options.length) {
								cursor = index - 1;
								toggle(index);
							}
							return;
						}
						if (matchesKey(data, Key.enter)) {
							if (selected.size > 0) done(normalizedIndexes([...selected]));
							return;
						}
						if (matchesKey(data, Key.escape)) done(null);
					},
				};
			});

			const details: QuizDetails = selectedOptions === null
				? baseDetails
				: {
						...baseDetails,
						selectedOptions,
						correct: sameIndexes(selectedOptions, correctOptions),
						cancelled: false,
					};

			return {
				content: [{ type: "text" as const, text: resultText(details) }],
				details,
			};
		},

		// Keep the pending tool call out of the transcript. The interactive quiz is
		// shown only in the temporary editor area until the user submits it.
		renderCall() {
			return new Container();
		},

		renderResult(result, _options, theme) {
			const details = result.details as QuizDetails | undefined;
			if (!details) {
				const content = result.content[0];
				return new Text(content?.type === "text" ? content.text : "", 0, 0);
			}
			if (details.cancelled) {
				return new Text(theme.fg("warning", "Quiz cancelled"), 0, 0);
			}

			const lines = [
				theme.fg("toolTitle", theme.bold("Multiple Choice Quiz")),
				theme.fg("text", details.question),
				"",
			];

			for (let index = 0; index < details.options.length; index++) {
				const number = index + 1;
				const selected = details.selectedOptions.includes(number);
				const correct = details.correctOptions.includes(number);
				let marker = "  ";
				let color: "text" | "success" | "error" | "muted" = "muted";
				if (selected && correct) {
					marker = "✓ ";
					color = "success";
				} else if (selected) {
					marker = "✗ ";
					color = "error";
				} else if (correct) {
					marker = "• ";
					color = "success";
				}
				lines.push(theme.fg(color, `${marker}${number}. ${details.options[index].label}`));
			}

			lines.push("");
			lines.push(
				details.correct
					? theme.fg("success", theme.bold("✓ Correct"))
					: theme.fg("error", theme.bold("✗ Incorrect")),
			);
			if (!details.correct) {
				lines.push(
					`${theme.fg("muted", "Correct answers:")} ${describeOptions(details.correctOptions, details.options)}`,
				);
			}
			if (details.explanation) lines.push(theme.fg("text", details.explanation));
			return new Text(lines.join("\n"), 0, 0);
		},
	});
}
