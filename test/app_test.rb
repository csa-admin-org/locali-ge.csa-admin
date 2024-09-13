ENV['RACK_ENV'] = 'test'

require 'bundler/setup'
Bundler.require(:default, :test)

require_relative '../app'
require "minitest/autorun"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app; App end

  def setup
    @secret = 'test_secret'
    ENV['WEBHOOK_SECRET'] = @secret
  end

  def request(payload, secret: nil)
    secret ||= @secret
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha256', secret, payload))

    header "Content-Type", 'application/json'
    header "X-WC-Webhook-Signature", signature

    post "/webhook", payload
  end

  def test_valid_webhook_request
    payload = File.read('test/fixtures/order_created.json')

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body
  end

  def test_unknown_store
    payload = { "store" => { "id" => 999, "name" => "Unknown" } }.to_json

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body
  end

  def test_invalid_signature
    payload = { "test_key" => "test_value" }.to_json

    request(payload, secret: "wrong_secret")

    assert_equal 403, last_response.status
    assert_equal "Forbidden", last_response.body
  end

  def test_missing_signature_header
    payload = { "test_key" => "test_value" }.to_json

    header "Content-Type", 'application/json'
    post "/webhook", payload

    assert_equal 403, last_response.status
    assert_equal "Forbidden", last_response.body
  end

  def test_invalid_json_payload
    payload = "invalid_json"

    request(payload)

    assert_equal 400, last_response.status
    assert_includes last_response.body, "Invalid JSON"
  end
end
