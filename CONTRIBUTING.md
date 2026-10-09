# Contributing

Thanks for wanting to help with MacStatusBar&Dock. A few short rules before opening a pull request:

## Before your first PR

By submitting a pull request, you agree to both of the following, for that contribution and any future ones:

1. **Developer Certificate of Origin (DCO).** You certify that you wrote the contribution yourself, or otherwise have the right to submit it under this project's license, and that you're submitting it under the project's license (GPL-3.0-only). This is the same DCO used by the Linux kernel and many other open-source projects; see [developercertificate.org](https://developercertificate.org/) for the full text. Please add a `Signed-off-by: Your Name <your@email>` line to your commits (`git commit -s`) confirming this.

2. **Relicensing grant.** In addition to licensing your contribution under GPL-3.0-only, you grant the project maintainer (besiktasliseba) a perpetual, worldwide, non-exclusive, royalty-free license to also use, modify, and relicense your contribution under different terms, including in closed-source or differently-licensed versions of this project or its components, at the maintainer's discretion. You keep your own copyright and can do whatever you like with your own contribution elsewhere; this just means the maintainer isn't locked out of using it outside GPL-3.0 later (for example, if a future native rewrite of part of this project isn't open source).

If you're not comfortable granting #2, please say so in your pull request and we can discuss it. Small, mechanical fixes (typos, obvious bugs) may not need it, but anything that becomes a meaningful part of the codebase generally does.

## Reporting bugs

Use Settings > Status Bar > Report a Problem on the iPad, or the bug report form when you open an issue. Please report security problems privately, as described in [SECURITY.md](./SECURITY.md).

## What's a good contribution

- Bug fixes, with a clear description of what was wrong and how you tested the fix.
- Small, focused pull requests, one topic at a time. Please don't reformat or reorder unrelated code in the same PR; the large `.x` files merge badly otherwise.
- If you're planning a bigger change (a new feature, a refactor), please open an issue first to discuss it before writing a lot of code.

## What this project can't easily accept

- Changes that can't be tested on a real iPad (this project has no CI/simulator story yet).
- New dependencies on other jailbreak tweaks beyond what's already required.

## Building and testing

How the parts fit together, how to build and which tests run on a Mac: [docs/development.md](./docs/development.md).

## Code style

- Comments explain *why*, not just *what*.
- New optional features default to **off**.
- Settings pages should look stock (standard cells, groups, short footers).

Questions? Open an issue.
