# frozen_string_literal: true

# Settings › Google Ads, kept in the core's Setting "google_ads": the OAuth
# client (its secret among the Setting's secrets), the developer token (a
# secret), the account signed in with (its refresh token a secret), which
# ad account to read (customer_id) and, when that account sits under a
# manager account, the manager's id (login_customer_id), and the accounts the
# sign-in can reach, to pick from.
class GoogleAds::Settings
  KEY = "google_ads"

  def self.current = new(Setting.get(KEY))

  # "123-456-7890" or "1234567890" → "1234567890".
  def self.customer_id(value) = value.to_s.delete("^0-9").presence

  def initialize(data)
    @data = data.to_h.stringify_keys
  end

  def client_id = @data["client_id"].presence
  def client_secret = Setting.secret(KEY, "client_secret").presence
  def developer_token = Setting.secret(KEY, "developer_token").presence
  def refresh_token = Setting.secret(KEY, "refresh_token").presence
  def client? = client_id.present? && client_secret.present?
  def connected? = refresh_token.present?
  def email = @data["email"]
  def connected_at = @data["connected_at"].presence&.then { Time.zone.parse(it) }

  def customer_id = self.class.customer_id(@data["customer_id"])
  def login_customer_id = self.class.customer_id(@data["login_customer_id"])
  def customer_name = accounts.find { it[1] == customer_id }&.first
  def api_version = @data["api_version"].presence || GoogleAds::API_VERSION
  def currency = @data["currency"].presence || "USD"
  def time_zone = @data["time_zone"].presence

  # Bumped by every change made through the plugin, so cached reports read fresh.
  def generation = @data["generation"].to_i

  def ready? = client? && developer_token.present? && connected? && customer_id.present?

  # What's missing before it can read, in the order to fix it.
  def missing
    [("the OAuth client" unless client?), ("the developer token" unless developer_token), ("the sign-in" unless connected?),
      ("the ad account" unless customer_id)].compact
  end

  # The ad accounts the sign-in reaches, as loaded after connecting: [[label, id, "manager"|nil, currency, time zone]].
  def accounts = Array(@data["accounts"])

  # From Settings › Google Ads' form or the API's PATCH: only what was sent changes.
  def self.update(params)
    params = params.to_h.stringify_keys
    data = {}
    data["client_id"] = params["client_id"].to_s.strip.presence if params.key?("client_id")
    if params.key?("customer_id")
      data["customer_id"] = customer_id(params["customer_id"])
      _, _, _, data["currency"], data["time_zone"] = current.accounts.find { it[1] == data["customer_id"] }
    end
    data["login_customer_id"] = customer_id(params["login_customer_id"]) if params.key?("login_customer_id")
    data["api_version"] = params["api_version"].to_s.strip[/\Av\d+\z/] if params.key?("api_version")
    Setting.set(KEY, data) if data.any?
    secrets = params.slice("client_secret", "developer_token").transform_values { it.to_s.strip }.compact_blank
    Setting.set_secret(KEY, secrets) if secrets.any?
    current
  end

  def self.remember(data) = Setting.set(KEY, data.stringify_keys)

  def self.changed! = remember("generation" => current.generation + 1)

  def self.connect(refresh_token:, email:)
    Setting.set_secret(KEY, "refresh_token" => refresh_token) if refresh_token.present?
    remember("email" => email, "connected_at" => Time.current.iso8601, "access_token_expires_at" => nil)
    Setting.set_secret(KEY, "access_token" => "")
  end

  def self.disconnect
    Setting.set_secret(KEY, "refresh_token" => "", "access_token" => "")
    remember("email" => nil, "connected_at" => nil, "accounts" => [])
  end

  def access_token
    token = Setting.secret(KEY, "access_token").presence
    expires = @data["access_token_expires_at"].presence&.then { Time.zone.parse(it) }
    token if expires && expires > 1.minute.from_now
  end

  def self.remember_access_token(token, expires_in)
    Setting.set_secret(KEY, "access_token" => token)
    remember("access_token_expires_at" => expires_in.to_i.seconds.from_now.iso8601)
  end

  def to_h
    {client_set: client?, developer_token_set: developer_token.present?, connected: connected?, email: email, connected_at: connected_at,
     customer_id: customer_id, customer_name: customer_name, login_customer_id: login_customer_id, api_version: api_version,
     currency: currency, time_zone: time_zone, accounts: accounts.map { {name: it[0], id: it[1], manager: it[2]} },
     ready: ready?, missing: missing}
  end
end
