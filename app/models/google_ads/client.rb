# frozen_string_literal: true

require "net/http"

# Talks to Google over Net::HTTP (a plugin may use only the gems the core
# bundles, so the Google Ads REST API rather than its gem): the OAuth
# web-server flow, then the Ads API with the developer token, the access
# token, and the manager account's id when there is one. The transport is
# injectable: specs answer without the network.
class GoogleAds::Client
  AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
  TOKEN_URL = "https://oauth2.googleapis.com/token"
  USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
  ADS_URL = "https://googleads.googleapis.com"
  TIMEOUT = 60
  MAX_PAGES = 20

  # A stand-in for the network, for specs: ->(method, url, headers, body) { [status, body] }.
  class << self
    attr_accessor :transport
  end

  def initialize(settings: GoogleAds::Settings.current, transport: nil)
    @settings = settings
    @transport = transport || self.class.transport || method(:http)
  end

  # Where a person signs in and grants the Ads API; offline, so a refresh token comes back.
  def authorize_url(redirect_uri:, state:)
    query = {client_id: @settings.client_id, redirect_uri: redirect_uri, response_type: "code", scope: ["openid", "email", GoogleAds::SCOPE].join(" "),
             access_type: "offline", prompt: "consent", state: state}
    "#{AUTH_URL}?#{URI.encode_www_form(query)}"
  end

  # The code from the callback for tokens: {refresh_token:, email:}.
  def exchange(code:, redirect_uri:)
    answer = token(grant_type: "authorization_code", code: code, redirect_uri: redirect_uri)
    GoogleAds::Settings.remember_access_token(answer["access_token"], answer["expires_in"])
    @settings = GoogleAds::Settings.current
    status, body = @transport.call(:get, USERINFO_URL, {"Authorization" => "Bearer #{answer["access_token"]}"}, nil)
    {refresh_token: answer["refresh_token"], email: (status.to_i == 200) ? parse(body)["email"] : nil}
  end

  # Every row a GAQL query returns, page after page, as Google writes them (camelCase, int64s as strings).
  def search(gaql, customer_id: @settings.customer_id)
    raise GoogleAds::Error, "Choose the ad account in Settings › Google Ads first" if customer_id.blank?

    rows = []
    page_token = nil
    MAX_PAGES.times do
      answer = ads(:post, "customers/#{customer_id}/googleAds:search", {query: gaql, pageToken: page_token}.compact)
      rows.concat(Array(answer["results"]))
      page_token = answer["nextPageToken"].presence
      break unless page_token
    end
    rows
  end

  # The ad accounts this sign-in reaches directly: ["1234567890", …].
  def accessible_customers
    Array(ads(:get, "customers:listAccessibleCustomers", nil)["resourceNames"]).map { it.delete_prefix("customers/") }
  end

  # A mutate call (campaignCriteria:mutate, campaigns:mutate, :uploadClickConversions…) on the chosen account.
  def mutate(path, body, customer_id: @settings.customer_id)
    raise GoogleAds::Error, "Choose the ad account in Settings › Google Ads first" if customer_id.blank?

    ads(:post, "customers/#{customer_id}#{path.start_with?(":") ? "" : "/"}#{path}", body)
  end

  private

  def ads(method, path, body, retried: false)
    raise GoogleAds::Error, "Add the developer token in Settings › Google Ads first" if @settings.developer_token.blank?

    headers = {"Authorization" => "Bearer #{access_token}", "developer-token" => @settings.developer_token, "Content-Type" => "application/json"}
    headers["login-customer-id"] = @settings.login_customer_id if @settings.login_customer_id
    status, response = @transport.call(method, "#{ADS_URL}/#{@settings.api_version}/#{path}", headers, body)
    if status.to_i == 401 && !retried
      GoogleAds::Settings.remember_access_token("", 0)
      @settings = GoogleAds::Settings.current
      return ads(method, path, body, retried: true)
    end
    answer = parse(response)
    raise GoogleAds::Error, failure(status, answer) unless status.to_i.between?(200, 299)

    answer
  end

  def access_token
    @settings.access_token || refresh
  end

  def refresh
    raise GoogleAds::Error, "Google Ads isn't connected: connect it in Settings › Google Ads" unless @settings.connected?

    answer = token(grant_type: "refresh_token", refresh_token: @settings.refresh_token)
    GoogleAds::Settings.remember_access_token(answer["access_token"], answer["expires_in"])
    @settings = GoogleAds::Settings.current
    answer["access_token"]
  end

  def token(**fields)
    raise GoogleAds::Error, "Add the OAuth client's ID and secret in Settings › Google Ads first" unless @settings.client?

    form = URI.encode_www_form(fields.merge(client_id: @settings.client_id, client_secret: @settings.client_secret))
    status, body = @transport.call(:post_form, TOKEN_URL, {"Content-Type" => "application/x-www-form-urlencoded"}, form)
    answer = parse(body)
    return answer if status.to_i == 200 && answer["access_token"].present?

    raise GoogleAds::Error, (answer["error"] == "invalid_grant") ? "Google no longer accepts this sign-in: connect it again in Settings › Google Ads" : failure(status, answer)
  end

  # Google Ads puts the useful part in error.details[].errors[].message.
  def failure(status, answer)
    errors = Array(answer.dig("error", "details")).flat_map { Array(it["errors"]) }.filter_map { it["message"] }.uniq
    detail = errors.first(3).join("; ").presence || answer.dig("error", "message") || answer["error_description"] ||
      (answer["error"].is_a?(String) ? answer["error"] : nil)
    case status.to_i
    when 401 then "Google didn't accept the sign-in#{": #{detail}" if detail}"
    when 403 then "Google Ads refused#{": #{detail}" if detail}"
    when 429 then "Google Ads is limiting requests#{": #{detail}" if detail}"
    else "Google Ads answered #{status}#{": #{detail.to_s.truncate(500)}" if detail}"
    end
  end

  def parse(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end

  def http(method, url, headers, body)
    uri = URI(url)
    request = {get: Net::HTTP::Get, post: Net::HTTP::Post, post_form: Net::HTTP::Post}.fetch(method).new(uri)
    headers.each { |name, value| request[name] = value }
    request.body = (method == :post_form) ? body : JSON.generate(body) if body
    Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: TIMEOUT) do |connection|
      response = connection.request(request)
      [response.code.to_i, response.body]
    end
  rescue Timeout::Error, IOError, SystemCallError, SocketError, OpenSSL::SSL::SSLError, Net::ProtocolError => problem
    raise GoogleAds::Error, "Couldn't reach Google Ads: #{problem.class.name.demodulize}"
  end
end
