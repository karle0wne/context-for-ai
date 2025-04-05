class ContextForAi < Formula
  desc "Generate a structured Markdown summary of your codebase for AI or documentation"
  homepage "https://github.com/karle0wne/context-for-ai"
  url "https://github.com/karle0wne/context-for-ai/releases/download/REPLACE_ME_WITH_VERSION/context-for-ai.tar.gz"
  sha256 "REPLACE_ME_WITH_SHA"
  license "MIT"
  version "REPLACE_ME_WITH_VERSION"

  def install
    bin.install "bin/context-for-ai"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/context-for-ai --version")
  end
end
