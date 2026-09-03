# frozen_string_literal: true

require "yaml"
require "net/http"
require "json"
require "uri"

class Webhook
  attr_reader :payload

  class Error < StandardError; end
  class UnkownStoreError < Error; end
  class IgnoredStatusError < Error; end
  class MemberCreationError < Error; end

  def self.handle!(payload)
    new(payload).handle!
  end

  def initialize(payload)
    @payload = payload
  end

  def handle!
    ensure_mapping!
    ensure_status_completed!

    submit_member!(member_params)
    member_params
  end

  private

  def ensure_mapping!
    return if mapping

    raise UnkownStoreError, "No mapping found for store: #{store_ids.join(", ")} (#{store_name})"
  end

  def ensure_status_completed!
    status = @payload["status"]
    return if status == "completed"

    raise IgnoredStatusError, "Order status is not completed: #{status}"
  end

  def submit_member!(params)
    response = api_request(Net::HTTP::Post, api_uri, params)
    return if response.code == "201"

    if duplicate_email_error?(response)
      update_existing_member!(params)
      return
    end

    raise MemberCreationError, member_failure_message(response, "Failed to create member")
  end

  def update_existing_member!(params)
    member = find_existing_member!(params[:emails])
    response = api_request(Net::HTTP::Patch, member_uri(member.fetch("id")), params)
    return if response.code.start_with?("20")

    raise MemberCreationError, member_failure_message(response, "Failed to update member")
  end

  def find_existing_member!(email)
    uri = api_uri
    uri.query = URI.encode_www_form(emails: email)
    response = api_request(Net::HTTP::Get, uri)
    unless response.code == "200"
      raise MemberCreationError, member_failure_message(response, "Failed to find existing member")
    end

    member = parse_members(response.body).find { |candidate| candidate.is_a?(Hash) && candidate["id"] }
    return member if member

    raise MemberCreationError, "Failed to find existing member for duplicate email"
  end

  def parse_members(body)
    data = JSON.parse(body)
    case data
    when Array
      data
    when Hash
      data.key?("id") ? [ data ] : Array(data["members"])
    else
      []
    end
  end

  def duplicate_email_error?(response)
    return false unless response.code == "422"

    Array(response_errors(response)["emails"]).any? { |message| duplicate_email_message?(message) }
  end

  def duplicate_email_message?(message)
    message.to_s.match?(/déjà utilisé|already been taken/i)
  end

  def response_errors(response)
    JSON.parse(response.body).fetch("errors", {})
  rescue JSON::ParserError
    {}
  end

  def member_failure_message(response, prefix)
    errors = response_errors(response)
             .map { |attr, msgs| "#{attr}: #{Array(msgs).join(", ")}" }
             .join("; ")
    "#{prefix} (#{response.code}): #{errors}"
  end

  def api_request(http_class, uri, body = nil)
    request = http_class.new(uri.request_uri, request_headers)
    request.body = body.to_json unless body.nil?
    http_client.request(request)
  end

  def member_uri(id)
    URI.parse("#{api_uri}/#{id}")
  end

  def http_client
    http = Net::HTTP.new(api_uri.host, api_uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if test_env?
    http
  end

  def request_headers
    {
      "Content-Type" => "application/json",
      "Authorization" => "Token token=#{api_token}"
    }
  end

  def member_params
    {
      name: "#{billing["last_name"]} #{billing["first_name"]}",
      emails: billing["email"],
      phones: billing["phone"],
      street: [ billing["address_1"], billing["address_2"] ].map(&:presence).compact.join(", "),
      city: billing["city"],
      zip: billing["postcode"],
      country_code: billing["country"],
      note: "Commande locali-ge.ch ##{@payload["id"]}",
      waiting_basket_size_id: mapping_id_for("basket_sizes"),
      waiting_depot_id: mapping_id_for("depots"),
      waiting_delivery_cycle_id: mapping_id_for("delivery_cycles"),
      members_basket_complements_attributes: basket_complements
    }
  end

  def mapping
    @mapping ||= YAML.load_file("./config/mapping.yml").detect do |_name, v|
      v["store_id"].in?(store_ids)
    end
  end

  def organization
    mapping.first
  end

  def api_token
    ENV.fetch("#{organization.upcase}_API_TOKEN", nil)
  end

  def api_uri
    url = mapping.last["api_endpoint"]
    url.gsub!(".ch", ".test") if test_env?
    URI.parse(url)
  end

  def basket_complements
    mapping_ids_for("basket_complements").map do |id|
      { basket_complement_id: id, quantity: 1 }
    end
  end

  def mapping_id_for(type)
    return unless mapping.last[type]

    mapping.last[type].map do |product_id, id|
      id if product_id.in?(product_ids)
    end.compact.last
  end

  def mapping_ids_for(type)
    ids = []
    mapping.last[type]&.each do |product_id, id|
      ids += Array(id) if product_id.in?(product_ids)
    end
    ids
  end

  def product_ids
    @product_ids ||= begin
      ids = []
      @payload.fetch("line_items").each do |item|
        ids << item["product_id"]
        ids += product_ids_from_meta(item["meta_data"])
      end
      ids.map(&:to_i)
    end
  end

  def product_ids_from_meta(meta_data)
    ids = []
    meta_data.each do |meta|
      next unless meta["key"] == "selected_item_post_id"

      meta["value"].each do |item_data|
        item_data.each_value { |id_data| ids += Array(id_data["value"]) }
      end
    end
    ids
  end

  def billing
    @billing ||= @payload.fetch("billing")
  end

  def store_id
    store_ids.first
  end

  def store_ids
    ids = []
    store = @payload["store"]
    ids << store["id"] if store.is_a?(Hash) && store["id"].present?
    ids += Array(@payload["stores"]).filter_map { |store| store["id"] if store.is_a?(Hash) && store["id"].present? }
    ids << meta_data_value("_dokan_vendor_id")

    ids.compact.map(&:to_i).uniq
  end

  def store_name
    store_names.join(", ")
  end

  def store_names
    names = []
    store = @payload["store"]
    names << store["name"] if store.is_a?(Hash)
    names << store if store.is_a?(String)
    names += Array(@payload["stores"]).filter_map { |store| store["name"] if store.is_a?(Hash) }

    names.compact.uniq
  end

  def meta_data_value(key)
    Array(@payload["meta_data"]).detect { |meta| meta.is_a?(Hash) && meta["key"] == key }&.fetch("value", nil)
  end

  def test_env?
    ENV["RACK_ENV"] == "test"
  end
end
