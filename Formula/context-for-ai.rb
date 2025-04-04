class ContextForAi < Formula
  desc "Generate a structured Markdown summary of your codebase for AI or documentation"
  homepage "https://github.com/karleowne/context-for-ai"
  url "https://github.com/karleowne/context-for-ai/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PUT_SHA256_HERE"
  license "MIT"

  def install
    bin.install "bin/context-for-ai"
  end

  test do
    system "#{bin}/context-for-ai", "--version"
  end
end
