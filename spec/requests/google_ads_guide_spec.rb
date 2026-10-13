# frozen_string_literal: true

require "rails_helper"
require_relative "../support/google_ads_helpers"

RSpec.describe "Google Ads guide", type: :request do
  include ActiveJob::TestHelper

  let(:admin) { create(:user) }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token!.token}", "Accept" => "application/json"}

  def claude_reply(json) = "Here's what I found, with reasoning.\n\n```json\n#{JSON.pretty_generate(json)}\n```\n"

  before do
    switch_plugin :google_ads, on: true
    fake_google_ads
    Rails.cache.clear
  end

  describe "the strategy, in the admin" do
    before { sign_in_as admin }

    it "starts at the first step, writes a prompt from what's known, and reads a pasted answer into the form for review" do
      get google_ads_strategy_path
      expect(response).to redirect_to(google_ads_strategy_step_path("business"))
      follow_redirect!
      expect(response.body).to include("The business and its offer", "Why this matters", "Copy prompt", "Customers and market")

      reply = claude_reply(business_name: "Healing Earth Design", sells: ["Seasonal planters for storefronts", "Commercial planting design"],
        not_sold: ["Lawn mowing", "Snow removal"], lead_offer: "Holiday displays for businesses", differentiators: ["Plants only"], proof: "40 five-star reviews")
      post google_ads_strategy_step_answer_path("business"), params: {answer: reply}
      expect(response.body).to include("Filled in from the answer", "Healing Earth Design", "Lawn mowing\nSnow removal")
      expect(GoogleAds::Brief.current.answer(:business_name)).to be_nil

      patch google_ads_strategy_step_path("business"), params: {answers: {business_name: "Healing Earth Design", sells: "Seasonal planters", not_sold: "Lawn mowing",
                                                                         lead_offer: "Holiday displays"}, next: "done"}
      expect(response).to redirect_to(google_ads_strategy_step_path("customers"))
      follow_redirect!
      expect(response.body).to include("Business name: Healing Earth Design", "What you don&#39;t sell, that people confuse with you: Lawn mowing")
    end

    it "fills a step with the install's AI, in the step's exact shape, for review before anything is saved" do
      get google_ads_strategy_step_path("customers")
      expect(response.body).to include("Fill it in with AI", "Or research it with Claude")
      expect(response.body).not_to include(">Fill with AI<")

      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      answer = {"segments" => ["Restaurants: storefronts that draw people in"], "not_customers" => ["Homeowners", "Job seekers"], "decision_makers" => "The owner",
                "service_area" => "Kent County", "buying_triggers" => ["A new location"], "seasonality" => "Displays are booked in October"}
      asked = nil
      allow(Ai).to receive(:structured) { |**options| asked = options; answer }

      expect { post google_ads_strategy_step_fill_path("customers") }.to have_enqueued_job(GoogleAds::FillJob)
      expect(response).to redirect_to(google_ads_strategy_step_path("customers", anchor: "research"))
      follow_redirect!
      expect(response.body).to include("The AI is researching this step")

      perform_enqueued_jobs
      expect(asked[:schema]).to include(type: "object", additionalProperties: false, required: %w[segments not_customers decision_makers service_area buying_triggers seasonality])
      expect(asked[:schema][:properties]["segments"]).to eq(type: "array", items: {type: "string"})
      expect(asked[:prompt]).to include("## Your task", "customer segments")

      get google_ads_strategy_step_path("customers")
      expect(response.body).to include("Filled in by the AI", "Homeowners\nJob seekers", "Kent County", "Fill it in again")
      expect(GoogleAds::Brief.current.answer(:service_area)).to be_nil

      patch google_ads_strategy_step_path("customers"), params: {answers: answer.merge("segments" => answer["segments"].join("\n"), "not_customers" => "Homeowners", "buying_triggers" => "A new location")}
      get google_ads_strategy_step_path("customers")
      expect(response.body).not_to include("Filled in by the AI")
      expect(GoogleAds::Brief.current.answer(:service_area)).to eq("Kent County")
    end

    it "says why when the AI fails, and fills list steps as changes to apply" do
      switch_plugin :ai, on: true
      Ai::Settings.update("provider" => "opencode", "api_key" => "zen-key")
      allow(Ai).to receive(:structured).and_raise(Ai::Error, "The provider timed out")
      post google_ads_strategy_step_fill_path("customers")
      perform_enqueued_jobs
      get google_ads_strategy_step_path("customers")
      expect(response.body).to include("finish: The provider timed out")

      allow(Ai).to receive(:structured).and_return("lists" => [{"name" => "Jobs", "description" => "Job seekers", "keywords" => ["jobs", "careers"]}])
      post google_ads_strategy_step_fill_path("exclusions")
      perform_enqueued_jobs
      get google_ads_strategy_step_path("exclusions")
      expect(response.body).to include("Here&#39;s what the AI&#39;s answer would change", "New list “Jobs”")
      expect(GoogleAds::ExclusionList.count).to eq(0)
    end

    it "reads a pasted answer wrapped in an object, or keyed by the questions' labels" do
      wrapped = claude_reply(customers: {"Customer segments" => ["Restaurants"], "notCustomers" => ["Homeowners"], "Service area" => "Kent County"})
      post google_ads_strategy_step_answer_path("customers"), params: {answer: wrapped}
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Filled in from the answer", "Restaurants", "Homeowners", "Kent County")

      post google_ads_strategy_step_answer_path("customers"), params: {answer: claude_reply(summary: "Nothing useful")}
      expect(response.body).to include("none of the keys this step asks for", "Fill it with AI")
    end

    it "says when a pasted answer can't be read" do
      post google_ads_strategy_step_answer_path("business"), params: {answer: "Sorry, I can't browse."}
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("There&#39;s no JSON in that answer")
    end

    it "shows whether the economics pay" do
      GoogleAds::Brief.current.tap { it.assign_answers("client_value" => "2400", "close_rate" => "20", "margin" => "50", "expected_cpc" => "8", "conversion_rate" => "5") }.save!
      get google_ads_strategy_step_path("economics")
      # A lead's worth $240; it costs 8 / 5% = $160; break-even CPC 240 × 5% = $12.
      expect(response.body).to include("$240.00", "$160.00", "$12.00", "Pays")
    end

    it "builds exclusion lists from an answer after showing what it would change, and syncs one to Google Ads" do
      reply = claude_reply(lists: [{name: "Jobs", keywords: ["jobs", "careers"]}, {name: "Maintenance", description: "Not offered", keywords: ["mowing", "[snow]"]}])
      post google_ads_strategy_step_answer_path("exclusions"), params: {answer: reply}
      expect(response.body).to include("What the answer would change", "New list “Maintenance”")
      expect(GoogleAds::ExclusionList.count).to eq(0)

      payload = Nokogiri::HTML5(response.body).at("input[name=payload]")["value"]
      post google_ads_strategy_step_apply_path("exclusions"), params: {payload: payload}
      expect(GoogleAds::ExclusionList.pluck(:name)).to contain_exactly("Jobs", "Maintenance")
      expect(GoogleAds::ExclusionList.find_by(name: "Maintenance").keyword_list).to eq([{text: "mowing", match_type: "PHRASE"}, {text: "snow", match_type: "EXACT"}])

      connect_google_ads
      list = GoogleAds::ExclusionList.find_by!(name: "Jobs")
      post sync_google_ads_exclusion_list_path(list)
      # Google's set "Jobs" (900) has jobs and salary: careers is added, salary removed.
      mutate = google_ads_requests.find { it[:url].include?("sharedCriteria:mutate") }[:body][:operations]
      expect(mutate).to contain_exactly({create: {sharedSet: "customers/1234567890/sharedSets/900", keyword: {text: "careers", matchType: "PHRASE"}}},
        {remove: "customers/1234567890/sharedCriteria/900~2"})
      expect(list.reload).to have_attributes(shared_set_id: "900", synced?: true)
    end
  end

  describe "a campaign, in the admin" do
    before { sign_in_as admin }

    it "takes a new plan into its guide, builds ad groups, keywords and ads from answers, and flags clashes with exclusion lists" do
      list = GoogleAds::ExclusionList.create!(name: "Maintenance", keywords: "mowing\nplanters")
      post google_ads_plans_path, params: {plan: {name: "Commercial", networks: "search", status: "planning"}}
      plan = GoogleAds::Plan.last
      expect(response).to redirect_to(google_ads_plan_guide_path(plan))
      follow_redirect!
      expect(response).to redirect_to(google_ads_plan_guide_step_path(plan, "goal"))

      structure = claude_reply(ad_groups: [{name: "Seasonal displays", theme: "Holiday planters", landing_path: "/business-seasonal-displays", why: "Season"}])
      post google_ads_plan_guide_step_answer_path(plan, "structure"), params: {answer: structure}
      post google_ads_plan_guide_step_apply_path(plan, "structure"), params: {payload: Nokogiri::HTML5(response.body).at("input[name=payload]")["value"]}
      expect(plan.ad_groups.first).to have_attributes(name: "Seasonal displays", landing_path: "/business-seasonal-displays")

      keywords = {ad_groups: [{name: "seasonal displays", keywords: ["\"commercial planters\"", "[storefront planters]", "\"holiday planters\""]}], campaign_negatives: ["wholesale"]}
      post google_ads_plan_guide_step_apply_path(plan, "keywords"), params: {payload: JSON.generate(keywords)}
      expect(plan.ad_groups.first.keyword_list.size).to eq(3)
      expect(plan.reload.negative_keywords.map { it[:text] }).to include("wholesale")

      ads = {ad_groups: [{name: "Seasonal displays", headlines: ["Seasonal Storefront Planters", "Holiday & Winter Displays", "For Businesses & HOAs"],
                          descriptions: ["Holiday displays now, spring color next.", "Plants only."], path1: "Seasonal", path2: "Planters"}]}
      post google_ads_plan_guide_step_apply_path(plan, "ads"), params: {payload: JSON.generate(ads)}
      expect(GoogleAds::Guide::Progress.new(plan.reload).status(GoogleAds::Guide.step(:ads))).to eq("done")

      patch google_ads_plan_guide_step_path(plan, "setup"), params: {answers: {networks: "search", bidding: "Manual CPC"}, exclusion_list_ids: [list.id]}
      expect(plan.reload.exclusion_list_ids).to eq([list.id])

      get google_ads_plan_guide_step_path(plan, "preflight")
      expect(response.body).to include("The negative “planters” blocks the keyword “commercial planters”", "Download for Ads Editor")
      get google_ads_plan_guide_step_path(plan, "keywords")
      expect(response.body).to include("Seasonal displays", "wholesale")
    end
  end

  describe "the API, for agents" do
    it "lists the steps, gives a step's prompt, applies an answer, and attaches exclusion lists to the campaign" do
      get "/api/google_ads/guide", headers: api_headers(admin)
      expect(response.parsed_body["next_step"]).to eq("business")
      expect(response.parsed_body["steps"].map { it["key"] }).to eq(%w[business customers economics competitors exclusions])

      get "/api/google_ads/guide/customers", headers: api_headers(admin)
      expect(response.parsed_body["prompt"]).to include("## Your task", "```json", "\"segments\"")

      post "/api/google_ads/guide/customers/answer", headers: api_headers(admin), as: :json,
        params: {answer: {segments: ["Restaurants: storefronts"], not_customers: ["Homeowners"], service_area: "Kalamazoo County"}, preview: true}
      expect(response.parsed_body).to include("applied" => false)
      expect(GoogleAds::Brief.current.answer(:segments)).to be_nil
      post "/api/google_ads/guide/customers/answer", headers: api_headers(admin), as: :json,
        params: {answer: claude_reply(segments: ["Restaurants: storefronts"], not_customers: ["Homeowners"], service_area: "Kalamazoo County")}
      expect(response.parsed_body["step"]).to include("status" => "done")
      expect(GoogleAds::Brief.current.answer(:segments)).to eq("Restaurants: storefronts")

      get "/api/google_ads/guide/economics", headers: api_headers(admin)
      expect(response.parsed_body["prompt"]).to include("Customer segments: Restaurants: storefronts")

      connect_google_ads
      list = GoogleAds::ExclusionList.create!(name: "Jobs", keywords: "jobs\nsalary", shared_set_id: "900")
      other = GoogleAds::ExclusionList.create!(name: "Residential", keywords: "homeowner")
      plan = GoogleAds::Plan.create!(name: "Commercial", campaign_id: "555", exclusion_list_ids: [list.id, other.id])
      get "/api/google_ads/plans/#{plan.id}", headers: api_headers(admin)
      expect(response.parsed_body["checks"].map { it["message"] }).to include(a_string_including("“Residential” isn't in Google Ads yet"))

      post "/api/google_ads/plans/#{plan.id}/exclusions", headers: api_headers(admin), as: :json
      expect(response.parsed_body["attached"]).to eq(["901"])
      attach = google_ads_requests.find { it[:url].include?("campaignSharedSets:mutate") }[:body][:operations]
      expect(attach).to eq([{create: {campaign: "customers/1234567890/campaigns/555", sharedSet: "customers/1234567890/sharedSets/901"}}])
    end

    it "keeps the guide to google_ads:plan and syncing to google_ads:write" do
      planner = create(:user, admin: false, role: create(:role, permissions: %w[google_ads:read google_ads:plan]))
      patch "/api/google_ads/guide/business", headers: api_headers(planner), params: {answers: {business_name: "Acme"}}, as: :json
      expect(response).to have_http_status(:ok)
      list = GoogleAds::ExclusionList.create!(name: "Jobs", keywords: "jobs")
      post "/api/google_ads/exclusion_lists/#{list.id}/sync", headers: api_headers(planner), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
