# Adaptive one-to-one teaching

> Inspired by [Eero Alvar, “How I Use AI to Learn Things”](https://www.youtube.com/watch?v=kzcI5F4tGiU) (2026-08-14, 18:58).

## Core idea

Use AI as a persistent one-to-one teaching interface. It can draw from many sources and perspectives, but it adapts the learning path and each explanation to one learner's current understanding.

Traditional learning is many-to-many. A teacher, book, or course is designed for many learners, so it cannot be optimal for any individual. At the same time, a learner switches among many sources, styles, notations, interfaces, and levels of reliability. That switching consumes attention that should go into understanding the subject.

An AI tutor can address both inefficiencies:

- **Optimize teaching:** work at the edge of the learner's understanding, skipping what they already know and postponing what they are not ready to understand.
- **Optimize mental-resource allocation:** absorb the logistics of finding sources, checking claims, choosing an order, and maintaining context.

The goal is not to make learning effortless. It is to preserve desirable difficulty in the subject while removing incidental friction around it.

## Probe → Plan → Teach

### Probe

Map the learner's current understanding with focused questions. Start with broad prerequisite branches, then narrow in on the boundary between known and unknown material. The workspace's mission, notes, and learning records are prior evidence, so a new session should not begin from zero.

The resulting learner model should capture:

- relevant existing knowledge;
- misconceptions and gaps;
- familiar terminology and notation;
- the target capability, not merely a topic label.

### Plan

Construct a dependency path from the learner's current state to the target capability. Verify factual claims against trusted sources and expose a compact version of the path to the learner.

Making the plan explicit gives the learner orientation and forces the tutor to reason through the teaching sequence instead of improvising an information dump. The plan is provisional: evidence from teaching can change it.

### Teach

Move through the path one reasoning step at a time. Adapt explanations, notation, examples, and visuals to the learner. Pause for questions and elicit evidence of understanding before advancing.

Frequent feedback matters because it:

1. distinguishes fluency or familiarity from durable understanding;
2. keeps the tutor's learner model calibrated;
3. strengthens learning through retrieval and application.

## How this maps to the `teach` skill

| Video concept | `teach` artifact or behavior |
|---|---|
| Persistent learner model | `MISSION.md`, `NOTES.md`, and `learning-records/` |
| Trusted aggregation of many sources | `RESOURCES.md` and lesson citations |
| Explicit dependency path | Compact learning-arc map before lessons |
| One reasoning step at a time | Short, tightly scoped lessons |
| Continuous comprehension checks | Interactive feedback and retrieval practice |
| Durable session output | Lessons, reference documents, and learning records |
| Consistent interface | The `teach` skill and shared lesson assets |

## Design principles

- Teach from demonstrated knowledge, not from an assumed average starting point.
- Treat the learner model as dynamic and revise it from observed performance.
- Use one stable interface without collapsing the diversity of underlying sources.
- Verify consistently: trust supports learning as well as correctness.
- Show the route, but deliver it in small steps.
- Prefer active recall and application over passive confirmation.
- Preserve useful state so future sessions begin where the learner actually is.

## Failure modes to avoid

- A long generic intake quiz that ignores existing learning records.
- Planning the whole topic rather than a path to a concrete capability.
- Showing an impressive graph that does not affect lesson order.
- Rushing through multiple conceptual steps before checking understanding.
- Treating “that makes sense” as proof that the learner can retrieve or use it.
- Using one AI interface as an excuse to rely on one unverified perspective.
- Generating artifacts without updating the persistent learner model.

## Compact operational prompt

> Help me learn **[topic]** so I can **[concrete capability]**. First use the existing teaching workspace, then probe only the prerequisites that remain uncertain, one question at a time. Build and show a verified dependency-based path. Teach one reasoning step at a time and regularly ask me to retrieve, predict, explain, or apply what I learned. Use my performance to adjust the path, and preserve durable changes in the workspace.
