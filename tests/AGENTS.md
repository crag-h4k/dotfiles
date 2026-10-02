# Test isolation and deployment evidence

Read `docs/ci.md` for the actual platform gate and `.pre-commit-config.yaml` for
the available hooks. Use the existing test style and fixtures for each subsystem.

- Ordinary tests use disposable homes, configs, destinations, runtime/state
  directories, and package-manager stubs. Do not install packages into the real
  account, refresh its sources, modify live overrides, or remove an existing
  home-directory test tree.
- Package-mode deployment tests are a separate, explicit operation in their
  controlled CI environments. Preserve fully unattended execution and run the
  installation as the fixture's non-root user.
- Tmux tests use separate servers/sockets. Do not kill or rewrite a user's live
  server to obtain isolation. Keep terminal-response and interactive prompt
  tests on a controlled pseudo-TTY.
- Exercise behavior: approved candidates match installation, current versions
  skip work, decline has no package side effects, merges preserve unknown keys,
  and failure leaves the previous runtime usable. Avoid asserting prose or
  private implementation details just because they are easy to match.
- Component coverage includes selected and unselected files/externals, each AI
  sub-feature, OS-specific output, and old/local state when relevant. Guidance
  under `home/` must be absent from all managed target lists and archives.
- Skill tests preserve unrelated local skills, resolve compatibility links to
  one canonical copy, and validate the deployed manifest and references offline.

Use the pinned Bats environment through prek; a global `bats` binary is not
required. If the hook fails but the suite passed elsewhere, reproduce the actual
hook, account, environment, and checkout. Report missing prerequisites explicitly.

Runtime deployment smoke checks must launch the managed applications and verify
their configuration and notifier behavior. Successful chezmoi exit status alone
does not establish a working workstation. Keep both native macOS and Trixie
deployment checks; improve their speed through caching and parallel jobs.
