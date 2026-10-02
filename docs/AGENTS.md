# Project documentation

Write for someone maintaining or deploying this workstation. State the behavior,
the command that controls it, and the evidence or limitation needed to use it.

- Keep engineering docs direct and conversational. Some dry irreverence fits;
  useful procedures take priority. The README can be louder and more playful.
- Preserve the established README voice, its compact badge row, and the notifier
  as a headline feature. Do not replace the copy with corporate marketing or add
  branding tiles merely to fill space. Avoid the term "rice" in public copy.
- Use familiar words, varied sentence lengths, and readable source line breaks.
  Cut assistant boilerplate, inflated claims, canned closers, decorative emphasis,
  and repeated contrasts. Avoid em dashes. Use the available unslop-text guidance
  for prose; explicitly invoked Humanizer retains its own invocation policy.
- Explain ownership and overrides accurately. Show public-safe example paths and
  placeholders. Keep real hostnames, identities, employer details, private
  endpoints, raw logs, transcripts, and credentials out of these files.
- Match documented commands, flags, source roots, and current hook names to the
  code. Use `prek`; `.pre-commit-config.yaml` remains the hook configuration.
  Distinguish behavior implemented on a feature branch from published releases.
- Maintain existing tables of contents and link targets. Use fenced code with a
  language and comply with `config/linters/markdownlint.yaml`.

Update affected docs in the same task as the behavior. Put contributor procedures
in CONTRIBUTING and detailed product behavior in its existing topic page. Keep
agent guidance discoverable through `docs/agent-guidance.md`; use the skill's
decisions reference for durable historical rationale. Do not paste a session
transcript, a task handoff, or a chronological work log into the README.
