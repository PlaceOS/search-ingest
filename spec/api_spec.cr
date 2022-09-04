require "./helper"

describe SearchIngest::Api do
  client = AC::SpecHelper.client

  it "health checks" do
    result = client.get SearchIngest::Api::NAMESPACE[0]
    result.success?.should be_true
  end

  it "should check version" do
    result = client.get "/api/search-ingest/v1/version"
    result.status_code.should eq 200
    PlaceOS::Model::Version.from_json(result.body).service.should eq "search-ingest"
  end
end
