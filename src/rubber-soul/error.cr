module RubberSoul
  class Error < Exception
    getter message

    def initialize(@message : String? = "")
      super(message)
    end
  end

  class CancelledError < Error
  end
end
