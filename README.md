## 🧾 context-for-ai

**context-for-ai** is a minimalistic CLI tool that generates a flat, machine-readable snapshot of your codebase — perfect for feeding into AI tools, automations, or static analysis pipelines.

Unlike the full-featured version, this tool avoids Markdown formatting and outputs raw content for each file in a simple, consistent format.

---

## ✨ Features

- 🧠 Machine-readable plain-text output
- 📄 Full content of `.kt`, `.java`, and `.py` source files
- 🧪 Smart file ordering: source files → tests → others
- ⚙️ Includes key project config files: `pom.xml`, `build.gradle.kts`, `requirements.txt`, etc.
- 🛠 No dependencies, no visual markup
- 🚀 Fast and IDE/AI-friendly

---

## 📦 Installation

### 📥 Via Homebrew (recommended)

```bash
brew tap karle0wne/homebrew-tap
brew install context-for-ai
```

### 📥 Or install directly

```bash
brew install --no-quarantine \
  https://raw.githubusercontent.com/karle0wne/homebrew-tap/main/Formula/context-for-ai.rb
```

### 🧪 Or run from source

```bash
git clone https://github.com/karle0wne/context-for-ai.git
cd context-for-ai
chmod +x bin/context-for-ai
./bin/context-for-ai --version
```

### 🌀 Or install via curl

```bash
curl -sSL https://raw.githubusercontent.com/karle0wne/context-for-ai/main/install.sh | bash
```

Optional flags:
- `--prefix /some/path` – custom install path (default: `/usr/local/bin`)
- `--force` – overwrite if already installed
- `--dry-run` – show what will happen, but don’t execute

---

## 🚀 Usage

From the root of your project:

```bash
context-for-ai
```

This generates a file called `project_snapshot.txt` with flat output like:

```
FILE: ./src/main/java/dev/vality/disputes/Servlet.java
package dev.vality.disputes;

...

FILE: ./tests/test_api.py
import pytest
...
```

---

## 📁 Output Format

- No Markdown
- Each file starts with: `FILE: ./relative/path`
- Followed by full raw content of the file
- One empty line between files

Perfect for:
- LLM input
- Parsing pipelines
- Automated review tooling

---

## 🛠 CLI options

```text
Usage:
  context-for-ai [--help] [--version]
```

---

## 💡 Use Cases

- AI codebase context serialization
- Automated static review or processing
- Lightweight backups
- Internal tooling integrations
- Code intelligence pipelines

---

## 📜 License

[MIT](LICENSE)
