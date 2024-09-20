require 'yaml'
require 'net/http'
require 'json'
require 'uri'

class Webhook
  attr_reader :payload

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

    store_name = @payload.dig("store", "name")
    raise "Skipped, no mapping found for store: #{store_id} (#{store_name})"
  end

  def ensure_status_completed!
    status = @payload["status"]
    unless status == "completed"
      raise "Skipped, order status is not completed: #{status}"
    end
  end

  def submit_member!(params)
    http = Net::HTTP.new(api_uri.host, api_uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE if test_env?

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Token token=#{api_token}"
    }
    request = Net::HTTP::Post.new(api_uri.path, headers)
    request.body = params.to_json

    response = http.request(request)
    unless response.code == "201"
      raise "Failed to create member: #{response.code}"
    end
  end

  def member_params
    {
      name: "#{billing["last_name"]} #{billing["first_name"]}",
      emails: billing["email"],
      phones: billing["phone"],
      address: [billing["address_1"], billing["address_2"]].map(&:presence).compact.join(', '),
      city: billing["city"],
      zip: billing["postcode"],
      country_code: billing["country"],
      note: "Commande locali-ge.ch ##{@payload["id"]}",
      waiting_basket_size_id: mapping_id_for("basket_sizes"),
      waiting_depot_id: mapping_id_for("depots"),
      members_basket_complements_attributes: basket_complements
    }
  end

  def mapping
    @mapping ||= YAML.load_file('./config/mapping.yml').detect { |name, v|
      v['store_id'] == store_id
    }
  end

  def organization
    mapping.first
  end

  def api_token
    ENV["#{organization.upcase}_API_TOKEN"]
  end

  def api_uri
    url = mapping.last["api_endpoint"]
    url.gsub!(/\.ch/, ".test") if test_env?
    URI.parse(url)
  end

  def basket_complements
    mapping_ids_for("basket_complements").map { |id|
      { basket_complement_id: id, quantity: 1 }
    }
  end

  def mapping_id_for(type)
    mapping.last[type]&.each { |product_id, id|
      return id if product_id.in?(product_ids)
    }
    nil
  end

  def mapping_ids_for(type)
    ids = []
    mapping.last[type]&.each { |product_id, id|
      ids << id if product_id.in?(product_ids)
    }
    ids
  end

  def product_ids
    @ids ||= begin
      ids =[]
      @payload.fetch("line_items").each { |item|
        ids << item["product_id"]
        item["meta_data"].each { |meta|
          if meta["key"] == "selected_item_post_id"
            meta["value"].each { |v| v.values.each { |v| ids += Array(v["value"]) } }
          end
        }
      }
      ids.map(&:to_i)
    end
  end

  def billing
    @billing ||= @payload.fetch("billing")
  end

  def store_id
    @payload.dig("store", "id")
  end

  def test_env?
    ENV["RACK_ENV"] == "test"
  end
end
