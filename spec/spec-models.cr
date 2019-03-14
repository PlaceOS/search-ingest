require "rethinkdb-orm"
require "time"

class RayGun < RethinkORM::Base
  attribute laser_colour : String = "red"
  attribute barrel_length : Float32 = 23.42
  attribute rounds : Int32 = 32
  attribute last_shot : Time = ->{ Time.utc_now }
end

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

SPEC_MODELS = [RayGun, Programmer, Coffee, Migraine]
