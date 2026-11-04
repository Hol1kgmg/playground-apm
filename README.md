# small-claude-temp

## Prerequisites

This project uses [mise](https://mise.jdx.dev/) for tool management.

If you haven't installed `mise` yet:

```bash
# Install mise (macOS)
brew install mise
# OR via curl
curl https://mise.run | sh

# Shell integration (for zsh)
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc
```

## Setup

```bash
mise run setup
```

This installs the tools in `mise.toml` and registers the `lefthook` pre-commit hook (gitleaks secret scan).
