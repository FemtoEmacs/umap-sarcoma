# How to guide a GenAI in explaining this project

This guide is for Luciano Lima, Thales Lima, and Pedro Fernandes. It will help
them reproduce the project results and, more importantly, test whether a GenAI
can explain those results to someone who knows neither UMAP nor programming.

## The human problem comes before the mathematical problem

While describing the inquiry that led him to recognize the limits of his own
knowledge, Socrates says in Plato's *Apology* (21d):

> ...τούτου γε σμικρῷ τινι αὐτῷ τούτῳ σοφώτερος εἶναι, ὅτι **ἃ μὴ οἶδα οὐδὲ οἴομαι εἰδέναι**.

The last words mean approximately, “What I do not know, I do not think I know.”
The Greek text can be checked in the
[Perseus Digital Library](https://www.perseus.tufts.edu/hopper/text?doc=Perseus%3Atext%3A1999.01.0170%3Atext%3DApol.%3Asection%3D21d).

The obstacle here is not merely an unfamiliar technical term. People become
accustomed to maps and stop noticing what maps do. Before saying “UMAP,” a
GenAI should reconstruct this forgotten knowledge:

1. The Earth is curved, but an ordinary map is flat. Two cities that are close
   on the Earth's surface appear as nearby points on the map. Preserving this
   neighborhood is one reason the map is useful.
2. Introduce a point through a meeting between two people. “In Toronto” still
   leaves many possible places; naming a building, a room, and one exact
   position progressively narrows the meeting place. Euclid's definition—a
   point is that which has no parts—separates the point's position from the dot
   of ink used to draw it.
3. Descartes showed that two numbers can specify the position of a point on a
   sheet of paper. These are its Cartesian coordinates.
4. The numbers need not represent a physical location. On a graph, height and
   weight can represent a person as a point and can be used to calculate body
   mass index. Adding age, blood pressure, and laboratory results creates
   points with three, four, or many coordinates.
5. Alphonse Bertillon took this idea into a concrete historical application.
   His identification system combined multiple body measurements, physical
   descriptions, and standardized photographs to distinguish individuals. The
   system is described by the
   [U.S. National Library of Medicine](https://www.nlm.nih.gov/exhibition/visibleproofs/galleries/technologies/bertillon.html).

Bertillon did not build UMAPs, and fingerprint identification later displaced
his system. His example belongs here because it shows how several measurements
can produce a description specific enough to distinguish one person. Each
measurement adds another dimension to the space of descriptions.

This is where the need for a map appears. A record described by one number can
be placed along a line, and a record described by two numbers can be placed on
a sheet of paper. Once every record needs many numbers, however, each point
belongs to a multidimensional space that people cannot easily picture. We must
bring those points back to a flat surface that our eyes can inspect—a table, a
piece of paper, or a computer screen—while preserving as much useful
neighborhood information as possible.

Imagine Bertillon spreading criminal identification cards across his table so
that he could compare them. The cards contained many measurements, but the
table offered only two physical directions in which to arrange them. He could
sort or place the cards according to selected similarities, turning the tabletop
into a simple two-dimensional visualization tool.  Modern scientists face the same visual problem with far more records and measurements. Instead of arranging cards by hand, they can use UMAP to calculate positions on a two-dimensional computer screen so that records judged similar from their many coordinates tend to remain near one another.

Only then should the GenAI reach the clinical problem. A piece of evidence may
have many characteristics: population, sarcoma type, therapy, endpoint,
follow-up time, and survival measurements. A computer can calculate with all
these dimensions, but a person cannot see them simultaneously. UMAP reduces
the description to a two-dimensional map and tries to keep evidence that was
similar in the multidimensional space close together. With that foundation in
place, clusters can be explained as groups of nearby points and the Transformer
as the component that learns to place new evidence on the fixed map without
recalculating the whole map.

## How to guide the GenAI

Do not ask only, “Explain UMAP.” That request allows a model to jump directly
to a memorized technical definition. Identify the reader, point to the document
containing the teaching sequence, and turn good explanation into observable
criteria. For example:

> Read `outline.md` before answering. Explain the project to a physician who
> has not studied computer science. Begin with the usefulness of a map and its
> preservation of neighborhoods. Explain a point, Euclid, Descartes' coordinates,
> height and weight, and then add dimensions. Only afterward introduce clinical
> evidence, UMAP, clusters, and the Transformer. Use simple sentences and
> concrete examples.

When evaluating the answer, ask:

- Did it begin with familiar experience or with jargon?
- Did it explain why a map is useful, or merely define UMAP?
- Did it show how two numbers become many dimensions?
- Did it say that proximity in the UMAP represents similarity under the chosen
  features?
- Did it distinguish the evidence map from statistical analysis and a clinical
  recommendation?

If the answer fails, identify the first missing step and request a new version.
Do not accept formal language as a substitute for understanding.

## One outline for different agents

[`outline.md`](../outline.md) is the canonical teaching outline. It prevents
each assistant from inventing a different explanation and leads the reader from
the familiar to the unfamiliar. Execution details belong in `README.md` and
`TOUR.md`; the outline should remain short, human, and conceptual.

For Codex, the repository uses [`AGENTS.md`](../AGENTS.md). The official
documentation says that Codex reads `AGENTS.md` files before starting work and
discovers instructions from the project root down to the current directory.
Start a new session in the repository root and request a summary. See
[Custom instructions with AGENTS.md](https://developers.openai.com/codex/guides/agents-md).

For Claude Code, [`CLAUDE.md`](../CLAUDE.md) imports `AGENTS.md` and
`outline.md` with `@file` syntax. Claude Code's documentation confirms that
imports are loaded into the context at the beginning of a session. The
`/context` command shows which memory files were actually loaded. See
[How Claude remembers your project](https://code.claude.com/docs/en/memory).

Loading an instruction and obeying it are different facts. Claude's own manual
notes that `CLAUDE.md` guides behavior but is not an infallible enforcement
layer. Test in a new session, save the question and response, and apply the
criteria above.

## What we tried with Gemini

With Gemini CLI, every attempt so far has failed to produce the intended
teaching sequence consistently:

1. We created [`GEMINI.md`](../GEMINI.md) with references to `AGENTS.md` and
   `outline.md`, following the arrangement that worked with the other agents.
2. We added a general `<ai_instructions>` block at the absolute top of
   `README.md`, telling the model to read `GEMINI.md` or `outline.md` before
   explaining the project.
3. To avoid confusing ChatGPT or Claude, we replaced it with a `<gemini_only>`
   route accompanied by `<openai_ignore />` and `<anthropic_ignore />`.
4. At Gemini's own suggestion, we made the instruction more explicit and
   imperative. We enumerated the intended order: the difficulty of seeing many
   measurements, the contrast with ordinary X and Y axes, and reduction to a
   two-dimensional map that preserves proximity.

None of these four attempts solved the problem in our tests. The XML in
`README.md` is an experiment suggested by Gemini, not a mechanism that we
consider validated. Do not hide this negative result, and do not conclude that
an instruction was obeyed merely because its file exists. Until we find a
reliable mechanism, put the teaching sequence directly in the request to
Gemini and evaluate its response step by step.

The main test is simple: does a person with no prior knowledge finish the
explanation understanding why a map is needed before hearing the name UMAP? If
the answer is no, the GenAI has not yet explained the project.
