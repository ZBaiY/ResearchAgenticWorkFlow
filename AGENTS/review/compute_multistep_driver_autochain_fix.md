# Driver-layer Autochain Fix (No Repo Code Changes)

- The strings `Ran set -euo pipefail ...` and narration-style lines are not emitted by repo runtime commands; they are command-wrapper narration outside `./bin/agenthub`.
- Repo scripts may contain `set -euo pipefail` in file headers, but that is script source text, not normal user-facing stdout markers.
- Driver invariant: after any CLI output containing `STOP_REASON=...`, permit at most one CLI command in that user turn and then stop.
- Driver must never auto-chain `review-accept` or `run --execute` in the same turn after a stop marker.
- Concrete gating suggestion: enforce a per-turn one-command budget with a turn nonce; once consumed by one CLI command, block further commands until next explicit user message.
