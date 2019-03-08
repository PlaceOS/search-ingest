require "rethinkdb-orm"
require "time"

class Programmer < RethinkORM::Base
  attribute name : String
end

class Coffee < RethinkORM::Base
  attribute temperature : Int32
  attribute created_at : Time = ->{ Time.utc_now }

  belongs_to Programmer, dependent: :destroy
end

class Migraine < RethinkORM::Base
  table :ouch
  attribute duration : Time = ->{ Time.utc_now + 50.years }

  belongs_to Programmer
end
