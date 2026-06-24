# YIELD: sourcetrait_ai_hypogeios

## Nushell MCP

### use paths
NU_LIB_DIRS wasn't being threaded through the stack on `commit()`. Fixed.

### .assets, .docs, security contstraints, and more
`install()` allows a per-library `.assets/` directory (static data)
to flow into the MCP's repository.

It also allows 'README.md', 'LEGAL.md' 'LICENSE.txt' and 'LICENSE-*.txt' files.

It allows a per-library `.docs/` directory ('*.md*') to carry up as well.

It blocks +x files as well as well-known executable extensions (.bash, .sh,
.py etc)


## Nushell nuances

### Nested tables in NUON via typed const
A `const FOO: record<...> = <NUON LITERAL>` works, but it *does not* currently
play well with nested `table<>` schemas.

## Porting methods

### Chain of Custody data via preserved / deviated / original

Porting process pulls data out of the historical repository and saves it
as '*.nuon' against a strictly typed schema documented in working knowledge
and enforced via infix return types and let/const schemas.

The first pass our own schema, calling mechanical extractors in
a 'dev' submodule that pull raw out of a repo. Intended to be accessed either:
- directly via `run()`
- indirectly via `call(<library>:dev/repo:build)`

These are typically defs labeled with a `model_<data_type>` convention.

The unaltered data is saved in `.assets/` under a `preserved/` directory.

The second pass generates *deviated* final product data, using preserved data
as the input. This comes in both mechanical and agentic forms.

Mechanical `derive_<data_type>` defs take preserved data and alter it for
the final product (based on how we want to flavor the port with enhancements
or changes).

Where ids (usually snake_case) are expected to be referenced
directly in code, we use a '<data_type>.pin.txt' to map old names to new names.

The second pass may include subagent calls, where re-formatting and summarizing
can occur. This is done by templating out subagent prompts along with a
driver prompt. The driver prompt instructs the driving agent on how to call
subagents and gives them filled out prompts to pass to each. It then instructs
on how to format the aggregated result to be passed to the next step in the
generation process. This data is expected to be NUON. We provide a strict
record schema that is somewhat self-documenting, and the generation functions
can then validate basic type correctness.

Data that is essential to the engine's operation are then auto-generated as
'.nu' scripts carrying a single `const MYDATA: <schema> = <NUON LITERAL>`

Otherwise, we construct data inspection methods for each data class that
typically lookup a flat-file database, per id.

Further, we pull text content out and place it in:
`.assets/locale/en_us/{preserved,deviated,original}`

Local data comes in two forms: terms (structure yaml) and prose (txt or md).

Preserved prose is typically in '.txt'. Deviated prose is re-formatted with
Markdown enhancements. Likewise for preserved vs deviated terms.

The entire build process can be re-initiated, creating a deterministic
data chain of custody that flows from:  
historical repository -> preserved data -> deviated data -> source-code

