# Cost policy: subagent launches

These rules apply to the primary agent and override any delegation guidance that
suggests launching multiple workers at once.

## Hard rules

1. Launch at most ONE subagent per response. Never emit a batched group of two
   or more subagent calls, even when a workflow prescribes parallel reviewers,
   parallel explorers, or a parallel lens group.
2. Wait for the subagent result before launching the next one, and only if the
   previous result is insufficient or the task genuinely needs a second worker.
3. Never launch a subagent to read what one `read`, `grep`, or `glob` call can
   answer directly. Inline tool work is always cheaper than a subagent.
4. If a workflow mandates parallel reviewers, run them one at a time and say so
   in the report. Sequential execution is the default; parallelism requires an
   explicit user request in the current turn.
5. Before the first subagent of a task, state in one line which agent and model
   will run, and why it cannot be done inline.

## Rationale

Parallel subagents reserve credit for every in-flight request simultaneously.
Three Opus-class workers can exceed the available credit and abort the whole
batch. Subagents also inherit the session model when no model is configured,
so an expensive session makes every fan-out expensive.

## Escalation

If a sequential run is rejected for insufficient credit, stop and report it.
Do not retry, do not reduce scope silently, and do not spawn a cheaper substitute
without telling the user.
