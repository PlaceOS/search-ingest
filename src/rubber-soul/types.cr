module RubberSoul::Types
  alias Table = NamedTuple(
    name: String,
    db: String)

  alias Service = NamedTuple(
    host: String,
    port: String)
end
