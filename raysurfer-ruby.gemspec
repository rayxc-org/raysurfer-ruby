# frozen_string_literal: true

require_relative "lib/raysurfer/version"

Gem::Specification.new do |spec|
  spec.name = "raysurfer-ruby"
  spec.version = Raysurfer::VERSION
  spec.authors = ["Raysurfer"]
  spec.email = ["raymond@raysurfer.com"]

  spec.summary = "Raysurfer Ruby SDK"
  spec.description = "AI maintained skills for vertical agents. Re-use verified code from prior runs instead of regenerating from scratch."
  spec.homepage = "https://www.raysurfer.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rayxc-org/raysurfer-ruby"
  spec.metadata["changelog_uri"] = "https://docs.raysurfer.com"

  spec.files = Dir.chdir(__dir__) do
    Dir[
      "lib/**/*.rb",
      "README.md",
      "LICENSE.txt"
    ]
  end
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.25"
  spec.add_development_dependency "rake", "~> 13.2"
end
