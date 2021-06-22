require "http"
require "json"
require "mutex"
require "uri"

require "placeos-models/version"

module RubberSoul
  class Client
    BASE_PATH   = "/api/rubber-soul"
    API_VERSION = "v1"
    DEFAULT_URI = URI.parse(ENV["RUBBER_SOUL_URI"]? || "http://rubber-soul:3000")
    getter api_version : String

    # Set the request_id on the client
    property request_id : String?

    getter uri : URI

    # A one-shot Core client
    def self.client(
      uri : URI = DEFAULT_URI,
      request_id : String? = nil,
      api_version : String = API_VERSION
    )
      client = new(uri, request_id, api_version)
      begin
        response = yield client
      ensure
        client.connection.close
      end

      response
    end

    # Queries
    ###########################################################################

    def healthcheck
      get("/").success?
    end

    def version : PlaceOS::Model::Version
      PlaceOS::Model::Version.from_json(get("/version").body)
    end

    # Reindexes Elasticsearch
    # If `backfill` is `true`, backfill data from RethinkDB into Elasticsearch
    def reindex(backfill : Bool = false)
      params = HTTP::Params{"backfill" => backfill.to_s}
      post("/reindex?#{params}").success?
    end

    # Backfill data from RethinkDB into Elasticsearch
    def backfill
      post("/backfill").success?
    end

    ###########################################################################

    def initialize(
      @uri : URI = DEFAULT_URI,
      @request_id : String? = nil,
      @api_version : String = API_VERSION
    )
      @connection = HTTP::Client.new(@uri)
    end

    @connection : HTTP::Client?

    protected def connection
      @connection.as(HTTP::Client)
    end

    protected getter connection_lock : Mutex = Mutex.new

    def close
      connection_lock.synchronize do
        connection.close
      end
    end

    # Base struct for responses
    private abstract struct BaseResponse
      include JSON::Serializable
    end

    # API modem
    ###########################################################################

    {% for method in %w(get post) %}
      # Executes a {{method.id.upcase}} request on core connection.
      #
      # The response status will be automatically checked and a `RubberSoul::Client::Error` raised if
      # unsuccessful.
      # ```
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType? = nil)
        path = File.join(BASE_PATH, API_VERSION, path)

        response = connection_lock.synchronize do
          connection.{{method.id}}(path, headers, body)
        end
        raise Error.from_response("#{uri}#{path}", response) unless response.success?

        response
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple`.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json)
      end

      # Executes a {{method.id.upcase}} request and yields a `HTTP::Client::Response`.
      #
      # When working with endpoint that provide stream responses these may be accessed as available
      # by calling `#body_io` on the yielded response object.
      #
      # The response status will be automatically checked and a RubberSoul::Client::Error raised if
      # unsuccessful.
      private def {{method.id}}(path, headers : HTTP::Headers? = nil, body : HTTP::Client::BodyType = nil)
        connection.{{method.id}}(path, headers, body) do |response|
          raise Error.from_response("#{@uri}#{path}", response) unless response.success?
          yield response
        end
      end

      # Executes a {{method.id.upcase}} request on the core client connection with a JSON body
      # formed from the passed `NamedTuple` and yields streamed response entries to the block.
      private def {{method.id}}(path, body : NamedTuple)
        headers = HTTP::Headers{
          "Content-Type" => "application/json"
        }
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end

      # :ditto:
      private def {{method.id}}(path, headers : HTTP::Headers, body : NamedTuple)
        headers["Content-Type"] = "application/json"
        headers["X-Request-ID"] = request_id unless request_id.nil?

        {{method.id}}(path, headers, body.to_json) do |response|
          yield response
        end
      end
    {% end %}

    class Error < ::Exception
      getter status_code

      def initialize(@status_code : Int32, message = "")
        super(message)
      end

      def initialize(path : String, @status_code : Int32, message : String)
        super("request to #{path} failed with #{message}")
      end

      def initialize(path : String, @status_code : Int32)
        super("request to #{path} failed")
      end

      def self.from_response(path : String, response : HTTP::Client::Response)
        new(path, response.status_code, response.body)
      end
    end
  end
end
