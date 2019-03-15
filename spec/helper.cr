require "spec"

# Application config
require "../src/config"
require "../src/rubber-soul"
require "../src/rubber-soul/*"

# Spec models
require "./spec_models"

# Helper methods for testing controllers (curl, with_server, context)
require "../lib/action-controller/spec/curl_context"
