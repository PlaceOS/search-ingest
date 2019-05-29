require "./helper"

class DummyResource
  enum Event
    GotIt
    Closed
  end

  def initialize(@channel : Channel(Event))
  end

  def sleep
    sleep @sleep
  end

  def got_it
    @channel.send(Event::GotIt)
  end

  def close
    @channel.send(Event::Closed)
  end
end

module RubberSoul
  describe Pool do
    it "should acquire a resource" do
      comm_channel = Channel(DummyResource::Event).new
      pool = Pool(DummyResource).new(initial_pool: 1) do
        DummyResource.new(comm_channel)
      end

      pool.available_resources.should eq 1

      spawn do
        comm_channel.receive.should eq DummyResource::Event::GotIt
        comm_channel.receive.should eq DummyResource::Event::Closed
      end

      pool.acquire do |resource|
        resource.should be_a(DummyResource)
        resource.got_it
      end

      pool.close
      pool.available_resources.should eq 0
    end
  end
end
