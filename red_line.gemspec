# frozen_string_literal: true

require_relative "lib/red_line/version"

Gem::Specification.new do |spec|
  spec.name = "red_line"
  spec.version = RedLine::VERSION
  spec.authors = ["Your Name"]
  spec.email = ["your.email@example.com"]

  spec.summary = "Distributed rate limiting for Ruby using Redis"
  spec.description = "A Redis-backed rate limiting library supporting concurrent, bucket, window, leaky bucket, and points-based limiters. Designed for multi-process applications."
  spec.homepage = "https://github.com/yourusername/red_line"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "redis-client", "~> 0.19"
  spec.add_dependency "connection_pool", "~> 2.4"
end
