require "log_helper"
require "simple_retry"
require "./constants"
require "./search-ingest/*"

module SearchIngest
  def self.wait_for_elasticsearch
    attempt = 0
    SimpleRetry.try_to(
      base_interval: 1.second,
      max_elapsed_time: 1.minute
    ) do
      attempt += 1
      Log.warn { "attempt #{attempt} connecting to #{SearchIngest::Elastic.settings.host}:#{SearchIngest::Elastic.settings.port}" } if attempt > 1

      # Ensure elastic is available
      raise "retry" unless SearchIngest::Elastic.healthy?
    end
  rescue
    abort("Failed to connect to Elasticsearch on #{SearchIngest::Elastic.settings.host}:#{SearchIngest::Elastic.settings.port}")
  end
end
