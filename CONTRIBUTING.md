# Contributing

This repo uses a **feature-branch + no-fast-forward merge** workflow for all changes. Every change — documentation, examples, playbook edits, skill tweaks, even small fixes — goes through a branch and gets merged into `main` with an explicit merge commit. The pattern matches the convention in [`staff-ds-interview-prep`](https://github.com/ruoyanhuang216/staff-ds-interview-prep) (this skill's parent reference repo).

## The workflow

### 1. Branch off `main`

Use a descriptive branch name with one of the standard prefixes:

| Prefix | What it's for | Example |
|---|---|---|
| `examples/<topic>` | A new worked example in `examples/` | `examples/stripe-sca-rollout` |
| `notes/<topic>` | Changes to the reference playbook or SKILL.md | `notes/fwer-fdr-expansion` |
| `docs/<topic>` | README, CONTRIBUTING, or other docs | `docs/install-troubleshooting` |
| `fix/<topic>` | Bug fixes or content corrections | `fix/spotify-cuped-typo` |

```bash
git checkout -b examples/new-example
```

### 2. Commit on the branch

Concise messages; one logical change per branch. If a single change is genuinely multiple things (e.g. a new example + a related playbook section), it's fine to do them on one branch, but write the commit message to enumerate them.

### 3. Merge with `--no-ff` back into `main`

The `--no-ff` flag is critical — it preserves the branch boundary in `git log --graph`. This lets you revert a single example by reverting its merge commit without affecting any other example.

```bash
git checkout main
git merge --no-ff examples/new-example -m "Merge branch 'examples/new-example'"
git push origin main
git branch -d examples/new-example
```

If you pushed the branch to the remote, also clean it up:

```bash
git push origin --delete examples/new-example
```

## Why this matters for a solo / small-team repo

- **Logical change boundaries** are preserved in `git log --graph` — each example, each playbook section change, each fix is a self-contained merge.
- **Reverting is one command** — `git revert -m 1 <merge-commit>` undoes the entire change cleanly.
- **Community PRs feel native** — the convention matches GitHub Flow, so external contributors don't have to learn a custom pattern.
- **Aligns with the sibling repo** ([`staff-ds-interview-prep`](https://github.com/ruoyanhuang216/staff-ds-interview-prep)) so muscle memory transfers.

## Adding a new worked example

If you're adding an example to `examples/`:

1. **Follow the existing structure** — first pass (the skill's output) + depth pass (the senior iteration) + final summary + key takeaways. The seven existing examples all follow this template.
2. **Use the prompt-as-block format** — show the actual `/ab-test-plan` invocation that produced the example.
3. **Cite the playbook** — when you reach for `§5.4 CUPED` or `§15.1 anytime-valid`, name the section so readers can drill into the depth.
4. **Add a row to the README's example table** with a one-sentence description of the dimension stressed.
5. **Commit on a branch named `examples/<your-example-name>`**.

## Adding a new playbook section or making playbook edits

The reference playbook (`reference/ab-testing-playbook.md`) is the depth source the skill reaches into. Edits to it:

1. **Branch named `notes/<topic>`** (mirrors the `staff-ds-interview-prep` convention).
2. **Don't break the section numbering** — if you add a new top-level section, renumber the related-notes section accordingly.
3. **Cross-references should be kept consistent** — when adding a citation, link the actual paper / blog inline.
4. **Mention in the commit message** which existing files in `examples/` reference the section, in case they need to be updated.

## Changing the skill itself

`skill/SKILL.md` defines the slash-command behavior. Changes here have user-visible consequences:

1. **Branch named `skill/<topic>`** — distinct prefix because these are behavior-changing.
2. **Verify the change doesn't break existing examples** — the seven examples in `examples/` are essentially regression tests; if the SKILL.md change would produce different output for any of them, document the expected diff in the commit.
3. **Manual test before push** — install the skill (or use the existing symlink) and invoke it on at least one example prompt to verify the change works end-to-end.

## License

By contributing, you agree your contributions are licensed under MIT (see [LICENSE](./LICENSE)).
