# frozen_string_literal: true

require "bundler/setup"
Bundler.require(:default)

Appsignal.load(:sinatra) # Load the Sinatra integration
Appsignal.start # Start AppSignal

require_relative "lib/webhook"

# Silence logs for non-webhook requests
Rack::CommonLogger.prepend(Module.new do
  def log(env, *)
    super if env["PATH_INFO"] == "/webhook"
  end
end)

# Sinatra only maps some Rack parse errors to BadRequest. Oversized query/form
# bodies raise QueryLimitError instead, which would 500 and hit AppSignal.
Sinatra::Request.prepend(Module.new do
  def params
    super
  rescue Rack::QueryParser::QueryLimitError => e
    raise Sinatra::BadRequest, "Invalid query parameters: #{Rack::Utils.escape_html(e.message)}"
  end
end)

class App < Sinatra::Base
  REQUIRED_BOOT_ENV = %w[WEBHOOK_SECRET APPSIGNAL_PUSH_API_KEY].freeze

  def self.require_boot_env!
    missing = REQUIRED_BOOT_ENV.select { |name| ENV[name].to_s.strip.empty? }
    raise "Missing required environment variables: #{missing.join(", ")}" if missing.any?
  end

  configure :production, :development do
    enable :logging
  end

  configure :production do
    require_boot_env!
  end

  before do
    @request_body = request.body.read
  end

  get "/up" do
    "<body style='background-color: green' />"
  end

  error Sinatra::BadRequest do
    env["sinatra.skip_appsignal_error"] = true
    status 400

    error = env["sinatra.error"]
    if error.message && error.message != error.class.name
      Rack::Utils.escape_html(error.message)
    else
      "<h1>Bad Request</h1>"
    end
  end

  post "/webhook" do
    verify_signature!
    payload = parse_payload

    begin
      member_params = Webhook.handle!(payload)
      logger.info "Member created with note: #{member_params[:note]}"
    rescue Webhook::UnkownStoreError, Webhook::IgnoredStatusError => e
      logger.info "#{e.class} - #{e.message}"
    rescue Webhook::MemberCreationError, TypeError, NoMethodError => e
      if e.is_a?(Webhook::MemberCreationError) && e.duplicate_email?
        logger.info "#{e.class} - #{e.message}"
      else
        Appsignal.report_error(e) do
          Appsignal.add_params(
            payload: payload,
            member_params: defined?(member_params) && member_params
          )
        end
      end
    end

    status 204
  end

  private

  def verify_signature!
    signature = request.env["HTTP_X_WC_WEBHOOK_SIGNATURE"]
    secret = ENV.fetch("WEBHOOK_SECRET", nil)

    computed_hmac = Base64.strict_encode64(
      OpenSSL::HMAC.digest("sha256", secret, @request_body)
    )

    return if signature.present? && Rack::Utils.secure_compare(computed_hmac, signature)

    warn "Webhook signature mismatch (body #{@request_body.bytesize} bytes)" if signature.present?

    halt 403, "Forbidden"
  end

  def parse_payload
    JSON.parse(@request_body)
  rescue JSON::ParserError
    halt 400, "Invalid JSON"
  end
end
