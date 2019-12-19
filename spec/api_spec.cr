require "./helper"

describe RubberSoul::API do
  # ==============
  # Test Responses
  # ==============
  with_server do
    it "health checks" do
      result = curl("GET", RubberSoul::API::NAMESPACE[0])
      result.success?.should be_true
    end
  end
end
