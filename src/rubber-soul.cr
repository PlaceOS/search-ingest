module RubberSoul
  VERSION = File.open("../shard.yml") { |f| YAML.parse(f)["version"] }
end

require "./rubber-soul/*"
