# frozen_string_literal: true

require "rails_helper"
require_relative "../support/google_ads_helpers"

RSpec.describe "Google Ads", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token!.token}", "Accept" => "application/json"}

  before do
    switch_plugin :google_ads, on: true
    fake_google_ads
    Rails.cache.clear
  end

  it "is a 404 while the plugin is off" do
    switch_plugin :google_ads, on: false
    sign_in_as admin
    get settings_google_ads_path
    expect(response).to have_http_status(:not_found)
    get "/api/google_ads", headers: api_headers(admin)
    expect(response).to have_http_status(:not_found)
  end

  describe "Settings › Google Ads" do
    before { sign_in_as admin }

    it "saves the client and developer token without reading the secrets back, and shows the redirect URI" do
      patch settings_google_ads_path, params: {google_ads: {client_id: "id.apps.googleusercontent.com", client_secret: "shh", developer_token: "dev-token", customer_id: "123-456-7890"}}
      expect(GoogleAds::Settings.current).to have_attributes(client_id: "id.apps.googleusercontent.com", client_secret: "shh", developer_token: "dev-token", customer_id: "1234567890")

      get settings_google_ads_path
      expect(response.body).to include("/settings/google_ads/callback", "Connect Google Ads")
      expect(Nokogiri::HTML5(response.body).at("a[href$='/settings/google_ads/connection/new']")).to be_present
      expect(response.body).not_to include("shh", "dev-token")
    end

    it "signs in with Google and back, checking the state, then lists the ad accounts and picks the only one that isn't a manager" do
      GoogleAds::Settings.update("client_id" => "id.apps.googleusercontent.com", "client_secret" => "shh", "developer_token" => "dev-token")

      get new_settings_google_ads_connection_path
      query = Rack::Utils.parse_query(URI(response.location).query)
      expect(query).to include("access_type" => "offline", "prompt" => "consent")
      expect(query["scope"]).to include("https://www.googleapis.com/auth/adwords")

      get settings_google_ads_callback_path, params: {code: "4/code", state: "forged"}
      expect(flash[:alert]).to include("didn't start here")

      get new_settings_google_ads_connection_path
      get settings_google_ads_callback_path, params: {code: "4/code", state: Rack::Utils.parse_query(URI(response.location).query)["state"]}
      expect(flash[:notice]).to include("owner@acme.example")
      settings = GoogleAds::Settings.current
      expect(settings).to have_attributes(ready?: true, customer_id: "1234567890", currency: "USD", time_zone: "America/Detroit", customer_name: "Healing Earth (123-456-7890)")
      expect(settings.accounts.map(&:third)).to eq([nil, "manager"])
      expect(google_ads_requests.find { it[:url].include?("googleAds:search") }[:headers]).to include("developer-token" => "dev-token")

      get settings_google_ads_path
      expect(response.body).to include("Agency MCC (999-888-7777) · manager")
      expect(response.body).not_to include("1//refresh", "ya29.access")
    end
  end

  describe "the Google Ads page" do
    before { sign_in_as admin }

    it "says what's missing until it's set up" do
      get google_ads_report_path
      expect(response.body).to include("Not connected yet", "the OAuth client")
    end

    it "shows the figures beside the period before, the campaigns and the search terms, and excludes one" do
      connect_google_ads
      get google_ads_report_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$300.00", "+200% (was $100.00)", "Commercial", "$30.00", "lawn mowing service")

      post google_ads_negative_keywords_path, params: {campaign_id: "555", keyword: "Lawn Mowing Service", days: 30}
      expect(flash[:notice]).to include("lawn mowing service")
      mutate = google_ads_requests.find { it[:url].include?("campaignCriteria:mutate") }
      expect(mutate[:url]).to end_with("/v25/customers/1234567890/campaignCriteria:mutate")
      expect(mutate[:body][:operations].first[:create]).to eq(campaign: "customers/1234567890/campaigns/555", negative: true, keyword: {text: "lawn mowing service", matchType: "PHRASE"})
      expect(AuditLog.where(action: "google_ads.negative_keywords_added")).to exist
    end

    it "says what Google refused" do
      connect_google_ads
      fake_google_ads(failing: {"googleAds:search" => "The developer token is only approved for use with test accounts."})
      get google_ads_report_path
      expect(response.body).to include("only approved for use with test accounts")
    end

    it "won't exclude for a role without google_ads:write" do
      connect_google_ads
      editor = create(:user, admin: false, role: create(:role, permissions: %w[google_ads:read]))
      sign_in_as editor
      get google_ads_report_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(">Exclude<")
      post google_ads_negative_keywords_path, params: {campaign_id: "555", keyword: "lawn"}
      expect(google_ads_requests.none? { it[:url].include?("mutate") }).to be(true)
    end
  end

  describe "the API" do
    before { connect_google_ads }

    it "reads the overview, days, campaigns, search terms, keywords and conversion actions" do
      get "/api/google_ads", headers: api_headers(admin), params: {days: 30}
      expect(response.parsed_body).to include("ready" => true)
      expect(response.parsed_body["totals"]).to include("cost" => 300.0, "clicks" => 40, "ctr" => 0.04, "cpc" => 7.5, "cost_per_conversion" => 100.0)
      expect(response.parsed_body["totals_before"]).to include("cost" => 100.0)

      get "/api/google_ads/daily", headers: api_headers(admin)
      expect(response.parsed_body["days"].map { it["cost"] }).to eq([60.5, 29.5])

      get "/api/google_ads/campaigns", headers: api_headers(admin), params: {from: "2026-09-01", to: "2026-09-30"}
      expect(response.parsed_body["period"]).to eq("from" => "2026-09-01", "to" => "2026-09-30")
      expect(response.parsed_body["campaigns"].first).to include("id" => "555", "daily_budget" => 30.0, "impression_share" => 0.42)

      get "/api/google_ads/search_terms", headers: api_headers(admin), params: {campaign_id: "555", limit: 10}
      expect(response.parsed_body["search_terms"].map { it["search_term"] }).to eq(["lawn mowing service", "commercial planters"])
      expect(google_ads_requests.last[:body][:query]).to include("campaign.id = 555", "LIMIT 10")

      get "/api/google_ads/keywords", headers: api_headers(admin)
      expect(response.parsed_body["keywords"].first).to include("keyword" => "commercial planters", "quality_score" => 7)

      get "/api/google_ads/conversion_actions", headers: api_headers(admin)
      expect(response.parsed_body["conversion_actions"].first).to include("id" => "321", "primary" => true)
    end

    it "runs read-only GAQL, and refuses anything else" do
      post "/api/google_ads/queries", headers: api_headers(admin), params: {query: "SELECT campaign.id FROM campaign"}
      expect(response.parsed_body).to include("count" => 1)

      post "/api/google_ads/queries", headers: api_headers(admin), params: {query: "DELETE everything"}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to include("Only SELECT")
    end

    it "adds negatives, pauses a campaign and uploads a conversion, each able to dry-run" do
      post "/api/google_ads/negative_keywords", headers: api_headers(admin), params: {campaign_id: "555", keywords: ["mowing", "Snow Plowing", "mowing"], match_type: "exact", validate_only: true}, as: :json
      expect(response.parsed_body).to include("added" => ["mowing", "snow plowing"], "match_type" => "EXACT", "validate_only" => true)
      expect(google_ads_requests.last[:body]).to include(validateOnly: true)
      expect(AuditLog.where(action: "google_ads.negative_keywords_added")).not_to exist

      patch "/api/google_ads/campaigns/555", headers: api_headers(admin), params: {status: "paused"}, as: :json
      expect(response.parsed_body).to include("status" => "PAUSED")
      expect(google_ads_requests.last[:body][:operations].first).to eq(update: {resourceName: "customers/1234567890/campaigns/555", status: "PAUSED"}, updateMask: "status")

      post "/api/google_ads/conversions", headers: api_headers(admin), params: {gclid: "EAIaIQ", conversion_action_id: "321", at: "2026-10-10 14:30", value: 2400}, as: :json
      expect(response).to have_http_status(:ok)
      conversion = google_ads_requests.last[:body][:conversions].first
      expect(conversion).to include(gclid: "EAIaIQ", conversionAction: "customers/1234567890/conversionActions/321", conversionValue: 2400.0, currencyCode: "USD")
      expect(conversion[:conversionDateTime]).to match(/\A2026-10-10 14:30:00[+-]\d\d:\d\d\z/)
    end

    it "keeps writes to google_ads:write and the settings' secrets to itself" do
      agent = create(:user, admin: false, role: create(:role, permissions: %w[google_ads:read]))
      get "/api/google_ads/campaigns", headers: api_headers(agent)
      expect(response).to have_http_status(:ok)
      patch "/api/google_ads/campaigns/555", headers: api_headers(agent), params: {status: "PAUSED"}, as: :json
      expect(response).to have_http_status(:forbidden)

      get "/api/google_ads/settings", headers: api_headers(admin)
      expect(response.parsed_body).to include("ready" => true, "customer_id" => "1234567890", "developer_token_set" => true)
      expect(response.body).not_to include("dev-token", "shh", "1//refresh")
    end

    it "says what's missing when it isn't set up" do
      GoogleAds::Settings.disconnect
      get "/api/google_ads", headers: api_headers(admin)
      expect(response.parsed_body).to eq("ready" => false, "missing" => ["the sign-in"])
      get "/api/google_ads/campaigns", headers: api_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to include("the sign-in")
    end
  end
end
