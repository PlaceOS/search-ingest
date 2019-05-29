module RubberSoul
  alias Parent = NamedTuple(name: String, index: String, routing_attr: Symbol)
  alias Associations = NamedTuple(parents: Array(Parent)?, children: Array(String)?)
end
