class RubberSoul::Error < Exception
  getter message

  def initialize(@message : String? = "")
    super(message)
  end
end
