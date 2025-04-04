# 🤖 context-for-ai

**context-for-ai** is a CLI tool that generates a clean, structured Markdown snapshot of your source code project — ideal for providing full context to AI systems, documentation tools, or just for human understanding.

---

## ✨ Features

- 📂 Pretty directory tree
- 📄 Source code blocks (partial or full)
- 📊 Project stats (file count, lines)
- 🧾 Extra files like `pom.xml`, `application.yml`, etc.
- 💬 Custom task prompt for AI agents
- 🛠 Interactive or one-shot CLI
- 🧱 Easy Homebrew install (`brew install`)
- 💥 Automatically includes `tree` if not installed

---

## 📦 Installation

### 📥 Via Homebrew (recommended)

```bash
brew tap karle0wne/tap
brew install context-for-ai
```

### Or install directly

```bash
brew install --no-quarantine \
  https://raw.githubusercontent.com/karle0wne/homebrew-tap/main/Formula/context-for-ai.rb
```

### Or run from source

```bash
git clone https://github.com/karle0wne/context-for-ai.git
cd context-for-ai
chmod +x bin/context-for-ai
./bin/context-for-ai --version
```

---

## 🚀 Usage

### Default (recommended)

```bash
context-for-ai --default
```

Includes `.kt` and `.java` files, the first 40 lines of each, and standard config files.

### Full content mode

```bash
context-for-ai --default --all
```

Includes the full content of each file.

### With AI prompt

```bash
context-for-ai --default --all --ask "What modules can be split from this project?"
```

Appends a `Task Prompt` block at the bottom of the file.

### Interactive mode

```bash
context-for-ai --interactive
```

Guided selection of file types, extras, and line limits.

---

## 🧪 Example Output

See [`examples/sample-output.md`](examples/sample-output.md)

---

## 📁 Output

Generates `project_description.md` with the following sections:

- 📁 Directory Structure
- 🔥 Recently Changed Files
- 📊 Project Stats
- 📄 Code Files
- ⚙️ Extra Config Files
- 💬 Task Prompt (optional)

---

## 🛠 CLI options

```bash
context-for-ai --help
```

```
Usage:
  context-for-ai [--default] [--all] [--ask "your question"]
  context-for-ai --interactive
  context-for-ai --version
  context-for-ai --help
```

---

## 📜 License

[MIT](LICENSE)

---

## 💡 Ideas for use

- AI assistant input (ChatGPT, Claude, CodeWhisperer, etc.)
- Developer onboarding
- Code reviews and refactoring
- Architecture mapping
- Internal documentation

### 🧪 Install without Homebrew

```bash
curl -sSL https://raw.githubusercontent.com/karle0wne/context-for-ai/main/install.sh | bash
```

Optional flags:
- `--prefix /some/path` – custom install path (default: `/usr/local/bin`)
- `--force` – overwrite if already installed
- `--dry-run` – show what will happen, but don’t execute
