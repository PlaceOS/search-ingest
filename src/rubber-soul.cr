require "semantic_version"

module RubberSoul
  VERSION = SemanticVersion.parse("1.0.1")
end

require "./rubber-soul/*"
