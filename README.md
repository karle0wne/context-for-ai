## 🧾 context-for-ai

**context-for-ai** is a minimalistic CLI tool that generates a flat, machine-readable snapshot of your codebase — ideal for AI models, static analysis, archiving, or custom automation.

It outputs a simple `project_snapshot.txt` file, listing every relevant file in order with full content and cryptographic hashes (MD5, SHA1) for integrity tracking.

---

## ✨ Features

- 📄 Full raw content of `.kt`, `.java`, `.py` files — or any extensions you choose
- 🧪 Smart file ordering: `src/` and `src/main/` → `test/` and `src/test/` → others
- 🛡 MD5 and SHA1 checksums for every file
- ⚙️ Includes config files like `pom.xml`, `requirements.txt`, `application.yml`, etc.
- 🔍 Recursively searches for config files, even in nested folders (e.g., `config/application.yml`)
- 🧠 Fully plain-text & machine-friendly — no Markdown
- 🧱 Zero dependencies — pure bash
- 🧰 Interactive mode for custom setup

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
  https://raw.githubusercontent.com/karle0wne/homebrew-tap/master/Formula/context-for-ai.rb
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
curl -sSL https://raw.githubusercontent.com/karle0wne/context-for-ai/master/install.sh | bash
```

Optional flags:
- `--prefix /some/path` – custom install path (default: `/usr/local/bin`)
- `--force` – overwrite if already installed
- `--dry-run` – show what will happen, but don’t execute

---

## 🚀 Usage

Run from your project root:

```bash
context-for-ai
```

This will generate a file `project_snapshot.txt` with entries like:

```
FILE: ./src/main/java/example/MyService.java
MD5:  d41d8cd98f00b204e9800998ecf8427e
SHA1: da39a3ee5e6b4b0d3255bfef95601890afd80709
package example;

public class MyService { ... }
```

---

### 🧰 Interactive Mode

Launch with:

```bash
context-for-ai -i
```

You will be prompted to:
- Enter file extensions (e.g., `kt,java,py`)
- Enter config filenames (e.g., `Dockerfile,build.gradle`)
- Enter custom output file name

---

## 📁 Output Format

Each file is written in this format:

```
FILE: ./relative/path
MD5:  <checksum>
SHA1: <checksum>
<file contents here>

[next file...]
```

Perfect for:
- 🤖 LLMs and context chunking
- 🔍 CI integrations and change diffing
- 📦 Lightweight archival
- 📊 Programmatic indexing and search

---

## 🛠 CLI options

```text
Usage:
  context-for-ai [--help] [--version] [-i]

Options:
  --help        Show this help message
  --version     Show script version
  -i            Interactive mode for custom config
```

---

## 💡 Use Cases

- AI assistant input (Claude, ChatGPT, local LLMs)
- Internal snapshot diffing
- Security integrity checks
- CI/CD preprocessing or static analysis
- Lightweight project serialization for tooling

---

## 📜 License

[MIT](LICENSE)
