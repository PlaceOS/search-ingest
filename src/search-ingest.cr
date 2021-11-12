require "log_helper"

require "./constants"
require "./search-ingest/*"

module SearchIngest
  def self.wait_for_elasticsearch
    Retriable.retry(
      max_elapsed_time: 1.minutes,
      on_retry: ->(_e : Exception, n : Int32, _t : Time::Span, _i : Time::Span) {
        Log.warn { "attempt #{n} connecting to #{SearchIngest::Elastic.settings.host}:#{SearchIngest::Elastic.settings.port}" }
      }
    ) do
      # Ensure elastic is available
      raise "retry" unless SearchIngest::Elastic.healthy?
    end
  rescue
    abort("Failed to connect to Elasticsearch on #{SearchIngest::Elastic.settings.host}:#{SearchIngest::Elastic.settings.port}")
  end
end
