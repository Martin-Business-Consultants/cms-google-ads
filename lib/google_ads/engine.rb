# frozen_string_literal: true

module GoogleAds
  # A CMS plugin (docs/plugins.md): it extends the core only through
  # Cms::Plugins, and the core never names it.
  class Engine < ::Rails::Engine
    initializer "google_ads.migrations" do |app|
      config.paths["db/migrate"].expanded.each { |path| app.config.paths["db/migrate"] << path }
    end

    initializer "google_ads.routes" do |app|
      app.routes.append do
        admin = proc do
          get "google_ads", to: "google_ads/reports#show", as: :google_ads_report
          post "google_ads/negative_keywords", to: "google_ads/negative_keywords#create", as: :google_ads_negative_keywords
          get "google_ads/strategy", to: "google_ads/guide#show", as: :google_ads_strategy
          scope "google_ads", module: "google_ads", as: "google_ads" do
            get "strategy/:step", to: "guide#show", as: :strategy_step
            patch "strategy/:step", to: "guide#update"
            post "strategy/:step/answer", to: "guide#answer", as: :strategy_step_answer
            post "strategy/:step/fill", to: "guide#fill", as: :strategy_step_fill
            post "strategy/:step/apply", to: "guide#apply", as: :strategy_step_apply
            post "strategy/:step/done", to: "guide#done", as: :strategy_step_done
            resources :exclusion_lists, except: :show do
              post :sync, on: :member
            end
            get "plans/:plan_id/guide", to: "guide#show", as: :plan_guide
            get "plans/:plan_id/guide/:step", to: "guide#show", as: :plan_guide_step
            patch "plans/:plan_id/guide/:step", to: "guide#update"
            post "plans/:plan_id/guide/:step/answer", to: "guide#answer", as: :plan_guide_step_answer
            post "plans/:plan_id/guide/:step/fill", to: "guide#fill", as: :plan_guide_step_fill
            post "plans/:plan_id/guide/:step/apply", to: "guide#apply", as: :plan_guide_step_apply
            post "plans/:plan_id/guide/:step/done", to: "guide#done", as: :plan_guide_step_done
            resources :plans do
              post :draft, on: :collection
              get :export, on: :member
              post :negatives, on: :member, action: :apply_negatives
              post :exclusions, on: :member, action: :attach_exclusions
              resources :ad_groups, only: [:new, :create, :edit, :update, :destroy], controller: "plan_ad_groups" do
                resource :landing_page, only: :create, controller: "landing_pages"
              end
              resources :tasks, only: [:create, :update, :destroy], controller: "plan_tasks"
            end
          end
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
            get "guide", to: "guide#index", as: :guide
            get "guide/:step", to: "guide#show", as: :guide_step
            patch "guide/:step", to: "guide#update"
            post "guide/:step/answer", to: "guide#answer", as: :guide_step_answer
            get "plans/:plan_id/guide", to: "guide#index", as: :plan_guide
            get "plans/:plan_id/guide/:step", to: "guide#show", as: :plan_guide_step
            patch "plans/:plan_id/guide/:step", to: "guide#update"
            post "plans/:plan_id/guide/:step/answer", to: "guide#answer", as: :plan_guide_step_answer
            resources :exclusion_lists, only: [:index, :show, :create, :update, :destroy] do
              post :sync, on: :member
            end
            resources :plans, only: [:index, :show, :create, :update, :destroy] do
              get :export, on: :member
              post :negatives, on: :member
              post :exclusions, on: :member
              resources :ad_groups, only: [:create, :update, :destroy], controller: "plan_ad_groups"
              resources :tasks, only: [:create, :update, :destroy], controller: "plan_tasks"
            end
          end
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :google_ads, name: "Google Ads", version: GoogleAds::VERSION, author: "Martin Business Consultants",
        enabled_by_default: false, requires: ">= 1.32", homepage: "https://github.com/Martin-Business-Consultants/cms-google-ads",
        description: "One Google Ads account: spend, clicks and conversions by day and campaign, search terms with one-click negatives, " \
                     "and offline conversions by gclid, in the admin, the API and the cms CLI."

      Cms::Plugins.permissions :google_ads, "Google Ads", %w[google_ads:read google_ads:plan google_ads:write],
        after: ["Google", "Leads", "Forms", "Globals"],
        defaults: {editor: %w[google_ads:read google_ads:plan], agent: %w[google_ads:read google_ads:plan]}
      Cms::Plugins.stylesheet :google_ads, "google_ads/google_ads"
      Cms::Plugins.menu :google_ads, :google_ads, label: "Google Ads", icon: "megaphone", group: "Content", after: [:market, :leads, :forms, :globals],
        path: -> { google_ads_report_path }, capability: "google_ads:read"
      Cms::Plugins.submenu :google_ads, :google_ads, label: "Figures", path: -> { google_ads_report_path }, capability: "google_ads:read"
      Cms::Plugins.submenu :google_ads, :google_ads, label: "Strategy", path: -> { google_ads_strategy_path }, capability: "google_ads:read"
      Cms::Plugins.submenu :google_ads, :google_ads, label: "Campaign plans", path: -> { google_ads_plans_path }, capability: "google_ads:read"
      Cms::Plugins.submenu :google_ads, :google_ads, label: "Exclusion lists", path: -> { google_ads_exclusion_lists_path }, capability: "google_ads:read"
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
      Cms::Plugins.api :google_ads, "/api/google_ads/plans",
        description: "Campaign plans: goal, budget, decision date, setup, ad groups (keywords, landing page, ad copy), negatives and a checklist with hints. " \
                     "GET one for its checks and the live campaign beside it; POST {plan: {..., ad_groups: [...]}, template}; google_ads:plan to change."
      Cms::Plugins.api :google_ads, "/api/google_ads/plans/:id/ad_groups", description: "A plan's ad groups (POST, PATCH, DELETE; google_ads:plan)."
      Cms::Plugins.api :google_ads, "/api/google_ads/plans/:id/tasks", description: "A plan's checklist: PATCH {done: true} ticks a task (google_ads:plan)."
      Cms::Plugins.api :google_ads, "/api/google_ads/plans/:id/export", description: "The plan as a CSV for Google Ads Editor's import."
      Cms::Plugins.api :google_ads, "/api/google_ads/plans/:id/negatives",
        description: "POST {validate_only}: add the plan's negatives the linked campaign doesn't have yet (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/guide",
        description: "The planning guide's strategy steps (and /api/google_ads/plans/:id/guide, a campaign's): where each stands. GET guide/:step for its questions, " \
                     "answers and a research prompt to run in Claude; PATCH {answers}; POST guide/:step/answer {answer: Claude's reply or its JSON, preview} to apply it."
      Cms::Plugins.api :google_ads, "/api/google_ads/exclusion_lists",
        description: "Negative keyword lists kept once by theme; POST :id/sync {validate_only} makes the shared set in Google Ads match (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/plans/:id/exclusions", description: "POST {validate_only}: sync the plan's exclusion lists and attach them to its campaign (google_ads:write)."
      Cms::Plugins.api :google_ads, "/api/google_ads/settings", description: "Settings › Google Ads (settings:read / settings:write; the secrets are never read back)."
    end
  end
end
