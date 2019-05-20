class RubberSoul::Error < Exception
  getter message

  def initialize(@message : String? = "")
    super(message)
  end

  class MappingFailed < Error
    def initialize(index : String, schema : String, response : HTTP::Client::Response)
      super("#{index}:\nschema: #{schema}\nES: #{response}")
    end
  end
end
