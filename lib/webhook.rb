require 'yaml'

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

    member_params
  end

  private

  def ensure_mapping!
    return if mapping

    store_name = @payload.dig("store", "name")
    raise ArgumentError, "No mapping found for store: #{store_id} (#{store_name})"
  end

  def member_params
    {
      organization: organization,
      name: "#{billing["last_name"]} #{billing["first_name"]}",
      emails: billing["email"],
      phones: billing["phone"],
      address: [billing["address_1"], billing["address_2"]].map(&:presence).compact.join(', '),
      city: billing["city"],
      zip: billing["postcode"],
      country_code: billing["country"],
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

  def basket_complements
    mapping_ids_for("basket_complements").map { |id|
      { basket_complement_id: id, quantity: 1 }
    }
  end

  def mapping_id_for(type)
    mapping.last[type].each { |product_id, id|
      return id if product_id.in?(product_ids)
    }
    nil
  end

  def mapping_ids_for(type)
    ids = []
    mapping.last[type].each { |product_id, id|
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
end
