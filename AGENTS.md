# Router access

- Connect to the OpenWrt router as `root` at `192.168.1.1` using `.local-ssh/id_ed25519_v2`.
- For a series of router commands, open one persistent SSH session and run the commands through that session. Reconnect only if the session ends or becomes unusable.
- A single, isolated command may use a one-off SSH connection.

## Setup and test history

- Record each setup action and test in the relevant phase document as it is performed. Include the date, cable/topology state, exact commands in execution order, command output and exit status, relevant configuration file contents or diffs, and the observed pass/fail result.
- Record failed attempts, corrections, retests, and rollback commands with their results. Clearly distinguish observed results from planned steps or assumptions; never mark an unrun check as complete.
- Put the evidence needed to verify the conclusion directly in the phase document. For very large output, include the relevant verbatim excerpt and the path and hash of the complete ignored local log. Redact passwords, private keys, and other credentials before recording.

## Token-efficient work

- Start with `git status --short` and the relevant headings or changed sections. Read entire documents only when a focused read cannot answer the question.
- Search with `rg` and keep shell output bounded. Use `rtk` for commands as instructed; remember that `rtk proxy` does not filter output. Avoid dumping whole files, tool catalogs, or long logs into the conversation.
- Batch independent checks. For router command series, use the persistent SSH session above and collect related read-only checks together. Do not repeat successful checks unless the state may have changed or a result needs confirmation.
- Keep large raw output out of the conversation while investigating; follow the setup and test history rules above when writing the phase document.
- For external references, search narrowly, prefer primary documentation, and reuse already verified links instead of fetching the same pages repeatedly.
- Keep each phase document current with completed checks, observed values, open questions, and rollback state. Use that concise record to hand off work to a new conversation when the current one becomes long.
- Use extra plugins or tools only when they provide a needed capability or clearly reduce repeated work; avoid broad tool discovery for a task that local commands can handle.
