# Changelog

## [1.4.0](https://github.com/crag-h4k/dotfiles/compare/v1.3.1...v1.4.0) (2026-10-20)


### Features

* **agent:** dirs prompt and plan rule ([#135](https://github.com/crag-h4k/dotfiles/issues/135)) ([e509df9](https://github.com/crag-h4k/dotfiles/commit/e509df90e1b54a2cacb4970b654f90a8e5e88225))
* **chezmoi:** add configurable worktrees and agents directories ([#133](https://github.com/crag-h4k/dotfiles/issues/133)) ([9cdb719](https://github.com/crag-h4k/dotfiles/commit/9cdb719d8daecb336569b1a3820cfd65e7ad920a))
* **chezmoi:** replace the two directory prompts with one optional editor page ([#138](https://github.com/crag-h4k/dotfiles/issues/138)) ([5d5f524](https://github.com/crag-h4k/dotfiles/commit/5d5f5242e754a665853cad109107f873e2abf71a))
* **npm:** bypass the release-age cooldown for chezmoi npm installs and updates ([#131](https://github.com/crag-h4k/dotfiles/issues/131)) ([4ff6ead](https://github.com/crag-h4k/dotfiles/commit/4ff6ead8941a725adbd0604929d105b03235ca68))
* **oc2:** return the leader to Ctrl+X and free the colliding keys ([#129](https://github.com/crag-h4k/dotfiles/issues/129)) ([0649c3f](https://github.com/crag-h4k/dotfiles/commit/0649c3f0c2510647a18173a20a78c44a03a8d8aa))


### Bug Fixes

* **chezmoi:** restore owner access to ~/.claude and skip the ~/.codex theme removal when it is unsearchable ([#136](https://github.com/crag-h4k/dotfiles/issues/136)) ([9ea665b](https://github.com/crag-h4k/dotfiles/commit/9ea665ba9130cf37c64883fd90a92f279c3c0de6))
* **chezmoi:** tolerate a missing or unreadable ~/.claude/skills in the migration ([#134](https://github.com/crag-h4k/dotfiles/issues/134)) ([4ace278](https://github.com/crag-h4k/dotfiles/commit/4ace2785f66e982371082e9812bd84d2bc0df88b))

## [1.3.1](https://github.com/crag-h4k/dotfiles/compare/v1.3.0...v1.3.1) (2026-10-17)


### Bug Fixes

* **tests:** prevent bare repo corruption ([#127](https://github.com/crag-h4k/dotfiles/issues/127)) ([e487b07](https://github.com/crag-h4k/dotfiles/commit/e487b07ca6c23a7cf531a6fc98b5017f3a837897))

## [1.3.0](https://github.com/crag-h4k/dotfiles/compare/v1.2.0...v1.3.0) (2026-10-17)


### Features

* **agents:** add portable Ricer subagent ([#89](https://github.com/crag-h4k/dotfiles/issues/89)) ([fda2a04](https://github.com/crag-h4k/dotfiles/commit/fda2a04c153f15b9fa58eb3f301a279e0866cd59))
* **ai:** unify skills and import Claude history ([#117](https://github.com/crag-h4k/dotfiles/issues/117)) ([dcbd08e](https://github.com/crag-h4k/dotfiles/commit/dcbd08e4aefc7646aba45a061b9da20bac07cf8d))
* **git:** add Lazygit and approval-gated PR workflows ([#104](https://github.com/crag-h4k/dotfiles/issues/104)) ([3f140f6](https://github.com/crag-h4k/dotfiles/commit/3f140f61897bd96ade33aec46aa1f73952738daf))
* **handoff:** integrate verified handoffs in active sessions ([c08e864](https://github.com/crag-h4k/dotfiles/commit/c08e864a56223f4911b963560f83e851c47b4397))
* **oc2:** add opt-in SSH MCP integration ([0901a30](https://github.com/crag-h4k/dotfiles/commit/0901a3088abb9df5d720d10d24a6268d81d9ce7b))
* **oc2:** add subagent-catalog to oc2 ([#93](https://github.com/crag-h4k/dotfiles/issues/93)) ([ef9724f](https://github.com/crag-h4k/dotfiles/commit/ef9724f35c29ddd14b8e5e865a6259c288d3a81b))
* **oc2:** generate a native V2 gud-lucent theme from the palette catalog ([#119](https://github.com/crag-h4k/dotfiles/issues/119)) ([b4018ee](https://github.com/crag-h4k/dotfiles/commit/b4018ee4a81581c8b38cd55a8b997ce8c1a9a253))
* **oc2:** integrate Caveman compression and recovery ([#102](https://github.com/crag-h4k/dotfiles/issues/102)) ([64ccd4b](https://github.com/crag-h4k/dotfiles/commit/64ccd4b7f0e0da74b11ab599e46619bc5f4879d5))
* **oc2:** integrate Pillbox and Sidequest ([#121](https://github.com/crag-h4k/dotfiles/issues/121)) ([3b9f6a1](https://github.com/crag-h4k/dotfiles/commit/3b9f6a163c2a8bbb237df12f27b1ad6f427dbc6d))
* **opencode:** add Build Plan Auto session modes ([#90](https://github.com/crag-h4k/dotfiles/issues/90)) ([036c819](https://github.com/crag-h4k/dotfiles/commit/036c819ad3a7fd2c3ca28e7854b7cc92b1ba1a67))
* **opencode:** stage inactive native priority tab sorter ([#91](https://github.com/crag-h4k/dotfiles/issues/91)) ([b429a86](https://github.com/crag-h4k/dotfiles/commit/b429a8696222a8354922e50a6ed314bb58bac37f))
* **openviking:** enable Agent Evolution and avoid empty Experience lookups ([b0c64fd](https://github.com/crag-h4k/dotfiles/commit/b0c64fde069424961f06cdc4b2ae55f0a615b755))
* **openviking:** local memory ([#96](https://github.com/crag-h4k/dotfiles/issues/96)) ([bb0357f](https://github.com/crag-h4k/dotfiles/commit/bb0357fe4c10b537bebafdebaf98131b436fe763))
* **privacy:** add Homebrew and Terraform telemetry opt-outs ([#103](https://github.com/crag-h4k/dotfiles/issues/103)) ([4bfda2f](https://github.com/crag-h4k/dotfiles/commit/4bfda2f8a67043622dacb1cb06a6205721f4fb12))
* **privacy:** opt out of telemetry in managed launch environments ([8a454c0](https://github.com/crag-h4k/dotfiles/commit/8a454c0c35ee4d7e3947b082480fd96aadc7debd))
* **tmux:** add rounded status pills ([#95](https://github.com/crag-h4k/dotfiles/issues/95)) ([9df184b](https://github.com/crag-h4k/dotfiles/commit/9df184b8ea575712d8dd46043c3d7570072a86a6))


### Bug Fixes

* **agents:** correct worktree context and shell search guidance ([#126](https://github.com/crag-h4k/dotfiles/issues/126)) ([f9f86d3](https://github.com/crag-h4k/dotfiles/commit/f9f86d3a6ebfc34313cdfe588dd8db27e636a975))
* **chezmoi:** preserve private MCP directory modes ([a02f05c](https://github.com/crag-h4k/dotfiles/commit/a02f05cec7a5f248ab850e8d2f9481e626546253))
* **chezmoi:** reconcile managed config drift ([#111](https://github.com/crag-h4k/dotfiles/issues/111)) ([763a8ee](https://github.com/crag-h4k/dotfiles/commit/763a8ee896834c7d89de95c17a91df7da6a8ed7b))
* **ci:** remove duplicate ARM64 prek job ([629e160](https://github.com/crag-h4k/dotfiles/commit/629e16028b5210678599519b19fec5cec2bcc251))
* **handoff:** make snapshot executable and allow both hook runners ([6b6907a](https://github.com/crag-h4k/dotfiles/commit/6b6907ad06b0786165cd20304f20e0de8742d651))
* **opencode:** limit Plan edits to handoff Markdown ([#88](https://github.com/crag-h4k/dotfiles/issues/88)) ([004c427](https://github.com/crag-h4k/dotfiles/commit/004c4274e695cab055629acea1c47dc960e0282f))
* **opencode:** manage Plan handoff permissions across machines ([a35662d](https://github.com/crag-h4k/dotfiles/commit/a35662d918654915de5f82bf6203b2579c7d5f72))
* **opencode:** merge managed plugins without dropping local entries ([#92](https://github.com/crag-h4k/dotfiles/issues/92)) ([57bd31c](https://github.com/crag-h4k/dotfiles/commit/57bd31c1823a76e9d7d7dbc92b344f324b887819))
* **opencode:** merge-manage cli.json so TUI settings survive apply ([#118](https://github.com/crag-h4k/dotfiles/issues/118)) ([598de36](https://github.com/crag-h4k/dotfiles/commit/598de36804ab45eabc5fe2b3eeafd8acbc87f3e5))
* **opencode:** notify only for pending attention ([9a1e47e](https://github.com/crag-h4k/dotfiles/commit/9a1e47ee6ea912833e909c7355d2d38a9f6b297c))
* **opencode:** repair pane alerts and Git approval policy ([17dd918](https://github.com/crag-h4k/dotfiles/commit/17dd918bf68e4082fa8f4f07f735f5fc27956865))
* **tmux:** prevent Termius status stacking ([#109](https://github.com/crag-h4k/dotfiles/issues/109)) ([a36aa88](https://github.com/crag-h4k/dotfiles/commit/a36aa886fae0a29f48eb9899dd7629c4612b0e2c))
* **tui:** oc2, tmux, npm ([#97](https://github.com/crag-h4k/dotfiles/issues/97)) ([e820b3d](https://github.com/crag-h4k/dotfiles/commit/e820b3d101bea335a07be529f2b919fb266fdeee))
* **updates:** fixes npm issues ([#94](https://github.com/crag-h4k/dotfiles/issues/94)) ([87dc0c7](https://github.com/crag-h4k/dotfiles/commit/87dc0c72a6628bc6c1bd1dc0d646d514a64ff51c))

## [1.2.0](https://github.com/crag-h4k/dotfiles/compare/v1.1.0...v1.2.0) (2026-10-02)


### Features

* **packaging:** modernize oc2 and package tooling and plan ([#78](https://github.com/crag-h4k/dotfiles/issues/78)) ([25c77f9](https://github.com/crag-h4k/dotfiles/commit/25c77f972716ca6c8d8cc913bff1b94625de8cfb))
* **tooling:** add resolved package plans and OpenCode terminal tooling ([#82](https://github.com/crag-h4k/dotfiles/issues/82)) ([58da11f](https://github.com/crag-h4k/dotfiles/commit/58da11fcbcdcf6e599680909a2bcfb780503d9ce))

## [1.1.0](https://github.com/crag-h4k/dotfiles/compare/v1.0.3...v1.1.0) (2026-09-30)


### Features

* **statusline:** adds copilot model cost to statusline  ([#75](https://github.com/crag-h4k/dotfiles/issues/75)) ([a123271](https://github.com/crag-h4k/dotfiles/commit/a123271a3306a2f0cdf51c0c0e21ca9408cfff56))

## [1.0.3](https://github.com/crag-h4k/dotfiles/compare/v1.0.2...v1.0.3) (2026-09-28)


### Bug Fixes

* **neovim:** fixes neovim hanging install ([#70](https://github.com/crag-h4k/dotfiles/issues/70)) ([f54d603](https://github.com/crag-h4k/dotfiles/commit/f54d60315c83346d42a660b1791850af86a2caf9))

## [1.0.2](https://github.com/crag-h4k/dotfiles/compare/v1.0.1...v1.0.2) (2026-09-27)


### Bug Fixes

* **opecode2:** compatibility with trixie opencode2 ([#68](https://github.com/crag-h4k/dotfiles/issues/68)) ([2d0dffc](https://github.com/crag-h4k/dotfiles/commit/2d0dffc916fbef45379e9760381209f8528317b7))

## [1.0.1](https://github.com/crag-h4k/dotfiles/compare/v1.0.0...v1.0.1) (2026-09-24)


### Bug Fixes

* **install:** package   plan and initial backups ([#66](https://github.com/crag-h4k/dotfiles/issues/66)) ([3743d69](https://github.com/crag-h4k/dotfiles/commit/3743d69974f2290b679b8ea6a2b7b130e840b882))

## [1.0.0](https://github.com/crag-h4k/dotfiles/compare/v0.4.0...v1.0.0) (2026-09-21)


### ⚠ BREAKING CHANGES

* Major restructure, remove support for opencode v1, various fixes

### Features

* Major restructure, remove support for opencode v1, various fixes ([7247712](https://github.com/crag-h4k/dotfiles/commit/72477129d22fc1bc1e2238e54e36d969a1d5b17d))

## [0.4.0](https://github.com/crag-h4k/dotfiles/compare/v0.3.0...v0.4.0) (2026-09-18)


### Features

* add unmanaged local override hatches for ghostty, tmux, zsh ([#59](https://github.com/crag-h4k/dotfiles/issues/59)) ([769729b](https://github.com/crag-h4k/dotfiles/commit/769729b9d020a31f6ae0c949c69a8b80a2010f5a))
* **opencode2-statusline:** Add initial opencode2 statusline, update … ([#62](https://github.com/crag-h4k/dotfiles/issues/62)) ([618d463](https://github.com/crag-h4k/dotfiles/commit/618d4639c13596f330ced57dfbdaf5c16f2e752d))
* **overrides:** add zsh, nvim, and git override configs ([#61](https://github.com/crag-h4k/dotfiles/issues/61)) ([1aaede3](https://github.com/crag-h4k/dotfiles/commit/1aaede35f548199d12d8cc8bb52f3297b7c1794c))

## [0.3.0](https://github.com/crag-h4k/dotfiles/compare/v0.2.0...v0.3.0) (2026-09-14)


### Features

* **opencode2:** add opencode2 config and integrate notifier ([#56](https://github.com/crag-h4k/dotfiles/issues/56)) ([3e522b2](https://github.com/crag-h4k/dotfiles/commit/3e522b2441e185cd6b9f1865106001ce748333df))
* **prettierd:** add json prettierd, fix neovim treesitter ([#52](https://github.com/crag-h4k/dotfiles/issues/52)) ([7fd980c](https://github.com/crag-h4k/dotfiles/commit/7fd980cf7dd17d7b4d0cbfc7892da8bd4fc95b70))

## [0.2.0](https://github.com/crag-h4k/dotfiles/compare/v0.1.0...v0.2.0) (2026-07-29)


### Features

* **git-delta:** add git-delta, fix nvim treesitter, add better nvim statusline ([#47](https://github.com/crag-h4k/dotfiles/issues/47)) ([117d984](https://github.com/crag-h4k/dotfiles/commit/117d984d3a7187df3700112735836e70519adf06))

## [0.1.0](https://github.com/crag-h4k/dotfiles/compare/v0.0.7...v0.1.0) (2026-07-28)


### Features

* **ci:** add headless macOS and Debian Trixie deployment validation ([02d4945](https://github.com/crag-h4k/dotfiles/commit/02d494513fb45c9050effa63dc4dfdc6e741a6b9))
* **griffo:** Add griffo trixie apt repos, ([#44](https://github.com/crag-h4k/dotfiles/issues/44)) ([07e8d5e](https://github.com/crag-h4k/dotfiles/commit/07e8d5ed27ea031ebc1bf4d566ea62586410ea78))
* **repo:** document and enforce the workstation workflow ([7dd22ea](https://github.com/crag-h4k/dotfiles/commit/7dd22ead10e22bd83d0820841a75f9e489041c8a))


### Bug Fixes

* **ci:** exclude the generated CHANGELOG from markdownlint ([#43](https://github.com/crag-h4k/dotfiles/issues/43)) ([bb36117](https://github.com/crag-h4k/dotfiles/commit/bb36117e831547bf956ea5b81b956737ab7912e3))
* **notify:** clear pane flag only on input notify fix ([#45](https://github.com/crag-h4k/dotfiles/issues/45)) ([65b8609](https://github.com/crag-h4k/dotfiles/commit/65b8609558c853a4d4336154f3949865b9a9b60e))
* run Release Please when pr-metadata is skipped on push ([#41](https://github.com/crag-h4k/dotfiles/issues/41)) ([095e2db](https://github.com/crag-h4k/dotfiles/commit/095e2db6b81e224e406b186bf2631b63b731a6ea))
