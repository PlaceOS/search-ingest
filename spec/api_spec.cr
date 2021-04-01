require "./helper"

describe RubberSoul::Api do
  # ==============
  # Test Responses
  # ==============
  with_server do
    it "health checks" do
      result = curl("GET", RubberSoul::Api::NAMESPACE[0])
      result.success?.should be_true
    end
  end
end
