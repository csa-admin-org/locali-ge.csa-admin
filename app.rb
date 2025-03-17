# frozen_string_literal: true

require 'bundler/setup'
Bundler.require(:default)

require_relative 'lib/webhook'

class App < Sinatra::Base
  configure :production, :development do
    enable :logging
  end

  before do
    @request_body = request.body.read
  end

  get '/up' do
    "<body style='background-color: green' />"
  end

  post '/webhook' do
    verify_signature!
    payload = parse_payload

    begin
      member_params = Webhook.handle!(payload)
      logger.info "Member created with note: #{member_params[:note]}"
    rescue Webhook::UnkownStoreError, Webhook::IgnoredStatusError => e
      logger.info "#{e.class} - #{e.message}"
    rescue Webhook::MemberCreationError => e
      logger.info payload
      logger.info member_params
      logger.info "#{e.class} - #{e.message}"
    rescue TypeError, NoMethodError => e
      logger.info payload
      logger.info "#{e.class} - #{e.message}"
    end

    status 204
  end

  private

  def verify_signature!
    signature = request.env['HTTP_X_WC_WEBHOOK_SIGNATURE']
    secret = ENV['WEBHOOK_SECRET']

    computed_hmac = Base64.strict_encode64(
      OpenSSL::HMAC.digest('sha256', secret, @request_body))

    unless signature && Rack::Utils.secure_compare(computed_hmac, signature)
      halt 403, 'Forbidden'
    end
  end

  def parse_payload
    JSON.parse(@request_body)
  rescue JSON::ParserError
    halt 400, 'Invalid JSON'
  end
end
