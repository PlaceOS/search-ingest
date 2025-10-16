require "log"
require "promise"
require "pg-orm"

require "./elastic"
require "./schemas"
require "./table"

# Class to manage pg-orm models sync with elasticsearch
module SearchIngest
  macro tables(models)
    {(%schemas = SearchIngest::Schemas.new({{ models.resolve }})),
      ([
        {% for model in models.resolve %}
        SearchIngest::Table({{ model }})
          .new(%schemas)
          .as(SearchIngest::Table::Interface),
        {% end %}
      ])
    }
  end

  class TableManager
    Log = ::Log.for(self)

    getter tables : Array(Table::Interface)
    getter? load_complete : Bool = false
    getter load_error : Exception? = nil
    @load_indicator : Channel(Nil) = Channel(Nil).new

    def initialize(
      @tables : Array(Table::Interface),
      backfill : Bool = false,
      watch : Bool = false,
    )
      Log.debug { {bulk_api: Elastic.bulk?, backfill: backfill, watch: watch, message: "starting TableManager"} }

      spawn do
        begin
          # Initialise indices to a consistent state
          initialise_indices(backfill)

          # Begin PostgresQL sync
          watch_tables if watch

          @load_complete = true
        rescue error
          @load_error = error
        ensure
          @load_indicator.close
        end
      end
    end

    def load_success? : Bool
      return false if @load_error
      return true if @load_complete

      @load_indicator.receive?
      load_success?
    end

    # Currently a reindex is triggered if...
    # - a single index does not exist
    # - a single mapping is different
    def initialise_indices(backfill : Bool = false)
      unless consistent_indices?
        Log.info { "reindexing all indices to consistency" }
        reindex_all
      end

      backfill_all if backfill
    end

    def watch_tables
      Promise.map(tables, &.start).get
    end

    # Save all documents in all tables to the correct indices
    def backfill_all : Bool
      Promise.map(tables, &.backfill.as(Bool)).get.all?
    end

    # Clear and update all index mappings
    #
    def reindex_all : Bool
      Promise.map(tables, &.reindex.as(Bool)).get.all?
    end

    # Checks if any index does not exist or has a different mapping
    #
    def consistent_indices?
      tables.all? &.consistent_index?
    end

    def stop
      tables.each(&.stop)
    end
  end
end
