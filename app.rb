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

class App < Sinatra::Base
  configure :production, :development do
    enable :logging
  end

  before do
    @request_body = request.body.read
  end

  get "/up" do
    "<body style='background-color: green' />"
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
      Appsignal.report_error(e) do
        Appsignal.add_params(
          payload: payload,
          member_params: defined?(member_params) && member_params
        )
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

    return if signature && Rack::Utils.secure_compare(computed_hmac, signature)

    halt 403, "Forbidden"
  end

  def parse_payload
    JSON.parse(@request_body)
  rescue JSON::ParserError
    halt 400, "Invalid JSON"
  end
end
