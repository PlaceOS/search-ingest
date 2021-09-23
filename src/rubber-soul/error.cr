class RubberSoul::Error < Exception
  getter message

  def initialize(@message : String? = "")
    super(message)
  end

  class MappingFailed < Error
    def initialize(index : String, schema : String, response : HTTP::Client::Response)
      super("index=#{index}, schema=#{schema}, elastic_error=#{response.body}")
    end
  end

  class PoolTimeout < Error
  end
end
