# frozen_string_literal: true

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

  def test_valid_webhook_request_cocagne
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read('test/fixtures/order_completed_cocagne.json')
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(status: 201)

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    assert_requested :post, "https://admin.cocagne.test/api/v1/members",
      times: 1,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Token token=api-token-cocagne"
      },
      body: {
        name: "Doe John",
        emails: "john@doe.ch",
        phones: "079 123 45 67",
        address: "Chemin de la Mairie, 1",
        city: "Troinex",
        zip: "1256",
        country_code: "CH",
        note: "Commande locali-ge.ch #35255",
        waiting_basket_size_id: 1,
        waiting_depot_id: 7,
        waiting_delivery_cycle_id: nil,
        members_basket_complements_attributes: [
          { basket_complement_id:10, quantity:1 }
        ]
      }.to_json
  end

  # def test_valid_webhook_request_locali
  #   ENV["LOCALI_API_TOKEN"] = "api-token-locali"
  #   payload = File.read('test/fixtures/order_completed_locali.json')
  #   stub_request(:any, "https://admin.panier-locali.test/api/v1/members")
  #     .to_return(status: 201)

  #   request(payload)

  #   assert_equal 204, last_response.status
  #   assert_empty last_response.body

  #   assert_requested :post, "https://admin.panier-locali.test/api/v1/members",
  #     times: 1,
  #     headers: {
  #       "Content-Type" => "application/json",
  #       "Authorization" => "Token token=api-token-locali"
  #     },
  #     body: {
  #       name: "Doe John",
  #       emails: "john@doe.ch",
  #       phones: "0791234567",
  #       address: "Chemin de la Mairie 1",
  #       city: "Genève",
  #       zip: "1205",
  #       country_code: "CH",
  #       note: "Commande locali-ge.ch #35717",
  #       waiting_basket_size_id: 1,
  #       waiting_depot_id: 3,
  #       members_basket_complements_attributes: []
  #     }.to_json
  # end

  def test_valid_webhook_request_touviere
    ENV["TOUVIERE_API_TOKEN"] = "api-token-touviere"
    payload = File.read('test/fixtures/order_completed_touviere.json')
    stub_request(:any, "https://admin.touviere.test/api/v1/members")
      .to_return(status: 201)

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    assert_requested :post, "https://admin.touviere.test/api/v1/members",
      times: 1,
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Token token=api-token-touviere"
      },
      body: {
        name: "Doe John",
        emails: "john@doe.ch",
        phones: "0791234567",
        address: "Chemin de la Mairie 1",
        city: "Genève",
        zip: "1205",
        country_code: "CH",
        note: "Commande locali-ge.ch #35715",
        waiting_basket_size_id: 2,
        waiting_depot_id: 3,
        waiting_delivery_cycle_id: nil,
        members_basket_complements_attributes: [
          { basket_complement_id: 2, quantity: 1 },
          { basket_complement_id: 1, quantity: 1 }
        ]
      }.to_json
  end

  def test_valid_webhook_request_but_not_completed
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read('test/fixtures/order_processing_cocagne.json')

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    assert_not_requested :post, "https://admin.cocagne.test/api/v1/members"
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
