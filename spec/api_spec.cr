require "./spec_helper"

describe RubberSoul::API do
  # ==============
  #  Unit Testing
  # ==============
  # it "should generate a date string" do
  #   # instantiate the controller you wish to unit test
  #   welcome = RubberSoul::API.new(context("GET", "/"))

  #   # Test the instance methods of the controller
  #   welcome.set_date_header[0].should contain("GMT")
  # end

  # ==============
  # Test Responses
  # ==============
  with_server do
    it "healthz" do
      result = curl("GET", "/api/healthz")
      result.success?.should be_true
    end
  end
end
