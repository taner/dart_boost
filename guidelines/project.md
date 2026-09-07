# Project rules

This project records its own decisions as rules, separately from the general
guidance above. Rules describe *this* codebase, and they outrank anything here
that contradicts them.

**Before planning or editing any file**, check `.ai/rules/index.md` if it
exists. Find the row whose globs match the file's path and read that rule file.
Read only the rows that match -- the index exists so that rules for parts of
the codebase you are not touching stay out of the way.

When you learn something durable about this project -- a settled decision, a
non-obvious trap, a standing constraint -- and the `record_rule` tool is
available, use it rather than writing a rule file by hand: the index is
regenerated on every recorded rule, and a hand-written file stays invisible to
other agents until it is. Do not record secrets, transient state, or anything
already obvious from the code.

When asked to infer this project's conventions, read
`.ai/infer-conventions.md` if it is present, and follow it.
