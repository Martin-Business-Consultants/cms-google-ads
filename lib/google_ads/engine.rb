# frozen_string_literal: true

module GoogleAds
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    initializer "google_ads.routes" do |app|
      app.routes.append do
        admin = proc do
          get "google_ads", to: "google_ads/reports#show", as: :google_ads_report
          post "google_ads/negative_keywords", to: "google_ads/negative_keywords#create", as: :google_ads_negative_keywords
          scope "settings", as: "settings" do
            resource :google_ads, only: [:show, :update], controller: "google_ads/settings" do
              # Connecting is a link (new), not a form: the admin's form-action policy
              # holds a form's redirect to Google's sign-in.
              resource :connection, only: [:new, :destroy], controller: "google_ads/connections"
              resource :callback, only: :show, controller: "google_ads/callbacks"
            end
          end
        end
        defined?(Cms::PATH) ? scope(path: Cms::PATH, &admin) : admin.call

        scope "api", defaults: {format: :json} do
          get "google_ads", to: "google_ads/api/overview#show", as: :api_google_ads
          scope "google_ads", module: "google_ads/api", as: "api_google_ads" do
            resource :settings, only: [:show, :update]
            get "daily", to: "reports#daily", as: :daily
            get "campaigns", to: "reports#campaigns", as: :campaigns
            get "search_terms", to: "reports#search_terms", as: :search_terms
            get "keywords", to: "reports#keywords", as: :keywords
            get "conversion_actions", to: "reports#conversion_actions", as: :conversion_actions
            post "queries", to: "queries#create", as: :queries
            post "negative_keywords", to: "changes#negative_keywords", as: :negative_keywords
            patch "campaigns/:id", to: "changes#campaign", as: :campaign
            post "conversions", to: "changes#conversions", as: :conversions
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :google_ads, name: "Google Ads", version: GoogleAds::VERSION, author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.32", homepage: "https://github.com/Martin-Business-Consultants/cms-google-ads",
        description: "One Google Ads account: spend, clicks and conversions by day and campaign, search terms with one-click negatives, " \
                     "and offline conversions by gclid, in the admin, the API and the cms CLI."

      Cms::Plugins.permissions :google_ads, "Google Ads", %w[google_ads:read google_ads:write],
        after: ["Google", "Leads", "Forms", "Globals"],
        defaults: {editor: %w[google_ads:read], agent: %w[google_ads:read]}
      Cms::Plugins.stylesheet :google_ads, "google_ads/google_ads"
      Cms::Plugins.menu :google_ads, :google_ads, label: "Google Ads", icon: "chart", group: "Content", after: [:market, :leads, :forms, :globals],
        path: -> { google_ads_report_path }, capability: "google_ads:read"
      Cms::Plugins.settings :google_ads, "Google Ads", -> { settings_google_ads_path },
        description: "Connect the Google Ads account: the OAuth client, the developer token, and which account to read.",
        capability: "settings:read"

      Cms::Plugins.api :google_ads, "/api/google_ads",
        description: "The account at a glance: spend, clicks, impressions, CTR, CPC, conversions and cost per conversion for ?days (default 30) beside the period before."
      Cms::Plugins.api :google_ads, "/api/google_ads/daily", description: "The account by day (?days or ?from&to): cost, clicks, impressions, conversions, value."
      Cms::Plugins.api :google_ads, "/api/google_ads/campaigns", description: "Each campaign's status, budget and figures for the range (?days or ?from&to)."
      Cms::Plugins.api :google_ads, "/api/google_ads/search_terms",
        description: "What people searched before clicking (?days, ?campaign_id, ?limit): the source of negative keywords."
      Cms::Plugins.api :google_ads, "/api/google_ads/keywords", description: "Keywords with match type, status, quality score and figures (?days)."
      Cms::Plugins.api :google_ads, "/api/google_ads/conversion_actions", description: "The account's conversion actions (ids for uploading offline conversions)."
      Cms::Plugins.api :google_ads, "/api/google_ads/queries", description: "POST a read-only GAQL query ({query: \"SELECT …\"}); rows as Google returns them (google_ads:read)."
      Cms::Plugins.api :google_ads, "/api/google_ads/negative_keywords",
        description: "POST {campaign_id, keywords: [...], match_type: PHRASE|EXACT|BROAD, validate_only}: add negative keywords to a campaign (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/campaigns/:id", description: "PATCH {status: PAUSED|ENABLED, validate_only}: pause or enable a campaign (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/conversions",
        description: "POST {gclid, conversion_action_id, at, value, currency, validate_only}: upload an offline conversion, e.g. a lead that became a client (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/settings", description: "Settings › Google Ads (settings:read / settings:write; the secrets are never read back)."
    end
  end
end
