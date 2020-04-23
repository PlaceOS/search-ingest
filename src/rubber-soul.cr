require "log_helper"

require "./constants"
require "./rubber-soul/*"

module RubberSoul
  Log         = ::Log.for("rubber-soul")
  LOG_BACKEND = ActionController.default_backend
end
