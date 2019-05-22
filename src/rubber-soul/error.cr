class RubberSoul::Error < Exception
  getter message

  def initialize(@message : String? = "")
    super(message)
  end

  class MappingFailed < Error
    def initialize(index : String, schema : String, response : HTTP::Client::Response)
      super("on #{index}:\nschema: #{schema}\nES: #{response.inspect}")
    end
  end
end
