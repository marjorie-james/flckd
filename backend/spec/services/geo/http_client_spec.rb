require "rails_helper"

# Exercises the shared geo HTTP boundary directly (timeouts, success check,
# error wrapping) — the resilience all geo clients inherit. Uses a throwaway
# subclass to reach the private get/post, hitting the real Faraday stack against
# WebMock (Constitution Principle II: recorded stubs, no live network).
RSpec.describe Geo::HttpClient do
  let(:base_url) { "http://geo.test" }

  let(:client_class) do
    Class.new(described_class) do
      def fetch(path) = get(path)
      def send_body(path, body) = post(path, body)
    end
  end

  subject(:client) { client_class.new(base_url: base_url, timeout: 2) }

  describe "on success" do
    it "returns the parsed JSON body for a GET" do
      stub_request(:get, "#{base_url}/ok")
        .to_return(status: 200, body: { "value" => 42 }.to_json,
                   headers: { "Content-Type" => "application/json" })

      expect(client.fetch("/ok")).to eq("value" => 42)
    end

    it "sends a JSON request body for a POST" do
      stub = stub_request(:post, "#{base_url}/echo")
        .with(body: { "a" => 1 }.to_json,
              headers: { "Content-Type" => "application/json" })
        .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      client.send_body("/echo", { a: 1 })
      expect(stub).to have_been_requested
    end
  end

  describe "on failure" do
    it "raises ServiceError including the status on a non-2xx response" do
      stub_request(:get, "#{base_url}/boom").to_return(status: 502, body: "bad gateway")

      expect { client.fetch("/boom") }
        .to raise_error(Geo::HttpClient::ServiceError, /returned 502/)
    end

    it "wraps a connection failure as an unreachable ServiceError" do
      stub_request(:get, "#{base_url}/down").to_raise(Faraday::ConnectionFailed.new("refused"))

      expect { client.fetch("/down") }
        .to raise_error(Geo::HttpClient::ServiceError, /unreachable/)
    end

    it "wraps a timeout as an unreachable ServiceError" do
      stub_request(:get, "#{base_url}/slow").to_timeout

      expect { client.fetch("/slow") }
        .to raise_error(Geo::HttpClient::ServiceError, /unreachable/)
    end
  end
end
