require './test/support'

describe Chromefoil::Client do
  let(:client) { Chromefoil::Client.new  }
  context "when initializing" do
    context "by default" do
      it "has a default starting point URL" do
        expect(client.starting_point_url).must_equal("http://localhost:9222/json")
      end
    end

    context "when customizing setup" do
      let(:client) { Chromefoil::Client.new host: "example.com", port: 1111 }
      it "retains the custom values" do
        expect(client.host).must_equal("example.com")
        expect(client.port).must_equal(1111)
      end
    end
  end


  describe "#remote_debugger_url" do
    it "has a value" do
      expect(client.remote_debugger_url).wont_be_nil
      expect(client.remote_debugger_url).must_equal('foo')
    end
  end
end
