require "rethinkdb-orm"
require "time"

abstract class AbstractBase < RethinkORM::Base
end

class RayGun < AbstractBase
  attribute laser_colour : String = "red"
  attribute barrel_length : Float32 = 23.42
  attribute rounds : Int32 = 32
  attribute last_shot : Time = ->{ Time.utc_now }
end

class Programmer < AbstractBase
  attribute name : String
end

class Coffee < AbstractBase
  attribute temperature : Int32
  attribute created_at : Time = ->{ Time.utc_now }

  belongs_to Programmer, dependent: :destroy
end

class Migraine < AbstractBase
  table :ouch
  attribute duration : Time = ->{ Time.utc_now + 50.years }

  belongs_to Programmer
end

SPEC_MODELS = [RayGun, Programmer, Coffee, Migraine]
