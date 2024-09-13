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
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read('test/fixtures/order_created.json')
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(status: 201)

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    # assert_requested :post, "https://admin.cocagne.test/api/v1/members",
    #   times: 1,
    #   headers: {
    #     "Content-Type" => "application/json",
    #     "Authorization" => "Token token=api-token-cocagne"
    #   },
    #   body: {
    #     name: "Doe John",
    #     emails: "john@doe.ch",
    #     phones: "079 123 45 67",
    #     address: "Chemin de la Mairie, 1",
    #     city: "Troinex",
    #     zip: "1256",
    #     country_code: "CH",
    #     waiting_basket_size_id: 1,
    #     waiting_depot_id: 22,
    #     members_basket_complements_attributes: [
    #       { basket_complement_id:10, quantity:1 }
    #     ]
    #   }.to_json
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
