# frozen_string_literal: true

ENV["RACK_ENV"] = "test"
ENV["APPSIGNAL_LOG"] = "stdout"

require "bundler/setup"
Bundler.require(:default, :test)

require_relative "../app"
require "minitest/autorun"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app = App

  def setup
    @secret = "test_secret"
    ENV["WEBHOOK_SECRET"] = @secret
  end

  def request(payload, secret: nil)
    secret ||= @secret
    signature = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha256", secret, payload)
    )

    header "Content-Type", "application/json"
    header "X-WC-Webhook-Signature", signature

    post "/webhook", payload
  end

  def with_reported_appsignal_errors
    reported = []
    original = Appsignal.method(:report_error)

    Appsignal.define_singleton_method(:report_error) do |error = nil, **_kwargs, &block|
      reported << error
      block&.call
    end

    yield
    reported
  ensure
    Appsignal.define_singleton_method(:report_error, original)
  end

  def test_valid_webhook_request_cocagne
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_completed_cocagne.json")
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
                       street: "Chemin de la Mairie, 1",
                       city: "Troinex",
                       zip: "1256",
                       country_code: "CH",
                       note: "Commande locali-ge.ch #35255",
                       waiting_basket_size_id: 1,
                       waiting_depot_id: 7,
                       waiting_delivery_cycle_id: nil,
                       members_basket_complements_attributes: [
                         { basket_complement_id: 10, quantity: 1 }
                       ]
                     }.to_json
  end

  def test_valid_webhook_request_filierealimentaire
    ENV["FILIEREALIMENTAIRE_API_TOKEN"] = "api-token-filierealimentaire"
    payload = File.read("test/fixtures/order_completed_filierealimentaire.json")
    stub_request(:any, "https://admin.filierealimentaire.test/api/v1/members")
      .to_return(status: 201)

    request(payload)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    assert_requested :post, "https://admin.filierealimentaire.test/api/v1/members",
                     times: 1,
                     headers: {
                       "Content-Type" => "application/json",
                       "Authorization" => "Token token=api-token-filierealimentaire"
                     },
                     body: {
                       name: "Doe John",
                       emails: "john@doe.ch",
                       phones: "0791234567",
                       street: "Chemin de la Mairie 1",
                       city: "Genève",
                       zip: "1205",
                       country_code: "CH",
                       note: "Commande locali-ge.ch #35717",
                       waiting_basket_size_id: 11,
                       waiting_depot_id: 3,
                       waiting_delivery_cycle_id: nil,
                       members_basket_complements_attributes: [
                         { basket_complement_id: 16, quantity: 1 },
                         { basket_complement_id: 17, quantity: 1 }
                       ]
                     }.to_json
  end

  def test_valid_webhook_request_touviere
    ENV["TOUVIERE_API_TOKEN"] = "api-token-touviere"
    payload = File.read("test/fixtures/order_completed_touviere.json")
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
                       street: "Chemin de la Mairie 1",
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

  def test_valid_webhook_request_with_stores_array
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = JSON.parse(File.read("test/fixtures/order_completed_cocagne.json"))
    payload["store"] = []
    payload["stores"] = [ { "id" => 31, "name" => "Jardins de Cocagne" } ]
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(status: 201)

    request(payload.to_json)

    assert_equal 204, last_response.status
    assert_empty last_response.body

    assert_requested :post, "https://admin.cocagne.test/api/v1/members", times: 1
  end

  def test_stores_array_without_mapping_is_unknown
    payload = {
      "store" => [],
      "stores" => [
        { "id" => 21, "name" => "Levain" },
        { "id" => 49, "name" => "Karibou &amp; Budé" }
      ],
      "status" => "completed"
    }

    error = assert_raises(Webhook::UnkownStoreError) do
      Webhook.handle!(payload)
    end

    assert_equal "No mapping found for store: 21, 49 (Levain, Karibou &amp; Budé)", error.message
  end

  def test_valid_webhook_request_but_not_completed
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_processing_cocagne.json")

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

  def test_duplicate_email_member_creation_is_not_reported_to_appsignal
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_completed_cocagne.json")
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(
        status: 422,
        body: { errors: { emails: [ "est déjà utilisé(e)" ] } }.to_json
      )

    reported = with_reported_appsignal_errors { request(payload) }

    assert_equal 204, last_response.status
    assert_empty last_response.body
    assert_empty reported
  end

  def test_duplicate_email_already_taken_is_not_reported_to_appsignal
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_completed_cocagne.json")
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(
        status: 422,
        body: { errors: { emails: [ "has already been taken" ] } }.to_json
      )

    reported = with_reported_appsignal_errors { request(payload) }

    assert_equal 204, last_response.status
    assert_empty reported
  end

  def test_other_member_creation_422_is_reported_to_appsignal
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_completed_cocagne.json")
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(
        status: 422,
        body: { errors: { waiting_depot_id: [ "n'est pas valide" ] } }.to_json
      )

    reported = with_reported_appsignal_errors { request(payload) }

    assert_equal 204, last_response.status
    assert_equal 1, reported.size
    assert_instance_of Webhook::MemberCreationError, reported.first
    assert_includes reported.first.message, "waiting_depot_id"
    refute reported.first.duplicate_email?
  end

  def test_member_creation_server_error_is_reported_to_appsignal
    ENV["COCAGNE_API_TOKEN"] = "api-token-cocagne"
    payload = File.read("test/fixtures/order_completed_cocagne.json")
    stub_request(:any, "https://admin.cocagne.test/api/v1/members")
      .to_return(status: 500, body: { errors: {} }.to_json)

    reported = with_reported_appsignal_errors { request(payload) }

    assert_equal 204, last_response.status
    assert_equal 1, reported.size
    assert_instance_of Webhook::MemberCreationError, reported.first
    refute reported.first.duplicate_email?
  end

  def test_duplicate_email_error_detection
    french = Webhook::MemberCreationError.new(
      "Failed to create member (422): emails: est déjà utilisé(e)",
      status_code: "422",
      errors: { "emails" => [ "est déjà utilisé(e)" ] }
    )
    english = Webhook::MemberCreationError.new(
      "Failed to create member (422): emails: has already been taken",
      status_code: "422",
      errors: { "emails" => [ "has already been taken" ] }
    )
    other422 = Webhook::MemberCreationError.new(
      "Failed to create member (422): waiting_depot_id: n'est pas valide",
      status_code: "422",
      errors: { "waiting_depot_id" => [ "n'est pas valide" ] }
    )
    server_error = Webhook::MemberCreationError.new(
      "Failed to create member (500): ",
      status_code: "500",
      errors: {}
    )

    message_only = Webhook::MemberCreationError.new(
      "Failed to create member (422): emails: est déjà utilisé(e)"
    )
    invalid_email = Webhook::MemberCreationError.new(
      "Failed to create member (422): emails: n'est pas valide",
      status_code: "422",
      errors: { "emails" => [ "n'est pas valide" ] }
    )

    assert french.duplicate_email?
    assert english.duplicate_email?
    assert message_only.duplicate_email?
    refute other422.duplicate_email?
    refute server_error.duplicate_email?
    refute invalid_email.duplicate_email?
  end

  def test_invalid_signature
    payload = { "test_key" => "test_value" }.to_json

    request(payload, secret: "wrong_secret")

    assert_equal 403, last_response.status
    assert_equal "Forbidden", last_response.body
  end

  def test_missing_signature_header
    payload = { "test_key" => "test_value" }.to_json

    header "Content-Type", "application/json"
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

  def test_malformed_multipart_request_is_not_reported_to_appsignal
    env = Rack::MockRequest.env_for(
      "/",
      method: "POST",
      "CONTENT_TYPE" => "multipart/form-data; boundary=missing",
      "CONTENT_LENGTH" => "1",
      input: "x"
    )

    status, _headers, body = app.call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    body.close if body.respond_to?(:close)

    assert_equal 400, status
    assert_includes response_body, "Invalid multipart/form-data"
    assert_equal true, env["sinatra.skip_appsignal_error"]
  end

  def test_oversized_form_request_is_not_reported_to_appsignal
    form = 4097.times.map { |i| "p#{i}=1" }.join("&")
    env = Rack::MockRequest.env_for(
      "/wp-admin/admin-ajax.php",
      method: "POST",
      "CONTENT_TYPE" => "application/x-www-form-urlencoded",
      "CONTENT_LENGTH" => form.bytesize.to_s,
      input: form
    )

    status, _headers, body = app.call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    body.close if body.respond_to?(:close)

    assert_equal 400, status
    assert_includes response_body, "exceeds limit"
    assert_equal true, env["sinatra.skip_appsignal_error"]
  end
end
