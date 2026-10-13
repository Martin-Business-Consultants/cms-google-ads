# frozen_string_literal: true

require "rails_helper"
require_relative "../support/google_ads_helpers"

RSpec.describe "Google Ads plans", type: :request do
  let(:admin) { create(:user) }

  def api_headers(user) = {"Authorization" => "Bearer #{user.api_token!.token}", "Accept" => "application/json"}

  def plan_payload
    {plan: {name: "Commercial", goal: "2 qualified commercial leads a month", success: "One client by January", daily_budget: 30,
            starts_on: "2026-10-20", decision_on: "2027-01-15", locations: "Kalamazoo County", campaign_id: "555",
            negatives: ["# Residential", "home", "backyard", "# Not offered", "[landscape architect]", "planters"],
            ad_groups: [{name: "Seasonal displays", landing_path: "/business-seasonal-displays",
                         keywords: ["\"commercial planters\"", "[storefront planters]", "seasonal planters for business"],
                         headlines: ["Seasonal Planters for Storefronts", "For Businesses & Property Managers Only Please", "Holiday Displays"],
                         descriptions: ["Entrances and planters for businesses, refreshed every season."]}]},
     template: "search_leads"}
  end

  before do
    switch_plugin :google_ads, on: true
    fake_google_ads
    Rails.cache.clear
  end

  describe "the API" do
    it "makes a plan from the template, with its ad groups, and checks it" do
      post "/api/google_ads/plans", headers: api_headers(admin), params: plan_payload, as: :json
      expect(response).to have_http_status(:created)
      plan = GoogleAds::Plan.last
      expect(plan.tasks.count).to eq(GoogleAds::PlanTemplate::TASKS.size)
      expect(plan.final_url_suffix).to include("utm_source=google")
      expect(plan.negative_keywords).to include({text: "landscape architect", match_type: "EXACT", group: "Not offered"}, {text: "home", match_type: "PHRASE", group: "Residential"})
      expect(response.parsed_body["ad_groups"].first["keywords"]).to include({"text" => "commercial planters", "match_type" => "PHRASE"}, {"text" => "seasonal planters for business", "match_type" => "BROAD"})

      get "/api/google_ads/plans/#{plan.id}", headers: api_headers(admin)
      messages = response.parsed_body["checks"].map { it["message"] }
      expect(messages).to include(
        a_string_including("Headline over 30 characters (46)"),
        a_string_including("it needs at least 2"),
        a_string_including("Broad match: seasonal planters for business"),
        a_string_including("Landing page /business-seasonal-displays isn't a page on this site"),
        a_string_including("The negative “planters” blocks the keyword “commercial planters”")
      )
      expect(response.parsed_body["checks"].first["level"]).to eq("problem")
    end

    it "ticks a task, and a weekly one comes due again" do
      plan = GoogleAds::Plan.from_template({name: "Test"}).tap(&:save!)
      task = plan.tasks.find_by!(repeats: "weekly")
      patch "/api/google_ads/plans/#{plan.id}/tasks/#{task.id}", headers: api_headers(admin), params: {done: true}, as: :json
      expect(response.parsed_body).to include("done" => true, "done_by" => admin.name)
      travel 8.days do
        expect(task.reload).not_to be_done
      end
    end

    it "compares the plan with its campaign, and applies the negatives it's missing" do
      connect_google_ads
      post "/api/google_ads/plans", headers: api_headers(admin), params: plan_payload, as: :json
      plan = GoogleAds::Plan.last

      get "/api/google_ads/plans/#{plan.id}", headers: api_headers(admin)
      live = response.parsed_body["live"]
      expect(live["campaign"]).to include("name" => "Commercial", "daily_budget" => 40.0, "display_network" => true)
      messages = response.parsed_body["checks"].map { it["message"] }
      expect(messages).to include(a_string_including("Display Network"), a_string_including("Budget is 40.00 a day; the plan says 30.00"))
      expect(live["missing_negatives"].map { it["text"] }).to eq(["home", "backyard", "landscape architect", "planters"])

      post "/api/google_ads/plans/#{plan.id}/negatives", headers: api_headers(admin), params: {validate_only: true}, as: :json
      expect(response.parsed_body).to include("added" => ["home", "backyard", "planters", "landscape architect"], "validate_only" => true)
      bodies = google_ads_requests.select { it[:url].include?("campaignCriteria:mutate") }.map { it[:body] }
      expect(bodies.map { it[:operations].first.dig(:create, :keyword, :matchType) }).to eq(%w[PHRASE EXACT])
    end

    it "exports a CSV for Google Ads Editor" do
      post "/api/google_ads/plans", headers: api_headers(admin), params: plan_payload, as: :json
      get "/api/google_ads/plans/#{GoogleAds::Plan.last.id}/export", headers: api_headers(admin)
      rows = CSV.parse(response.body, headers: true)
      expect(rows.first.to_h).to include("Campaign" => "Commercial", "Campaign Daily Budget" => "30.0", "Networks" => "Google search", "Campaign Status" => "Paused")
      expect(rows.map { [it["Keyword"], it["Criterion Type"]] }).to include(["commercial planters", "Phrase"], ["storefront planters", "Exact"], ["landscape architect", "Negative Exact"])
      ad = rows.find { it["Ad type"] == "Responsive search ad" }
      expect(ad.to_h).to include("Headline 1" => "Seasonal Planters for Storefronts", "Final URL" => a_string_ending_with("/business-seasonal-displays"))
    end

    it "keeps planning to google_ads:plan and applying to google_ads:write" do
      reader = create(:user, admin: false, role: create(:role, permissions: %w[google_ads:read]))
      planner = create(:user, admin: false, role: create(:role, permissions: %w[google_ads:read google_ads:plan]))
      post "/api/google_ads/plans", headers: api_headers(reader), params: plan_payload, as: :json
      expect(response).to have_http_status(:forbidden)
      post "/api/google_ads/plans", headers: api_headers(planner), params: plan_payload, as: :json
      expect(response).to have_http_status(:created)
      post "/api/google_ads/plans/#{GoogleAds::Plan.last.id}/negatives", headers: api_headers(planner), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "the admin" do
    before { sign_in_as admin }

    it "makes a plan, adds an ad group, ticks the checklist and shows the checks" do
      get google_ads_plans_path
      expect(response.body).to include("Plan before you spend")

      post google_ads_plans_path, params: {plan: {name: "Commercial", daily_budget: "30", networks: "search", status: "planning"}, template: "search_leads"}
      plan = GoogleAds::Plan.last
      expect(response).to redirect_to(google_ads_plan_guide_path(plan))

      post google_ads_plan_ad_groups_path(plan), params: {ad_group: {name: "Seasonal", landing_path: "/nowhere", keywords: "\"commercial planters\"", headlines: "One\nTwo\nThree", descriptions: "A\nB"}}
      expect(plan.ad_groups.count).to eq(1)

      task = plan.tasks.first
      patch google_ads_plan_task_path(plan, task)
      expect(task.reload).to be_done

      post google_ads_plan_tasks_path(plan), params: {task: {title: "Call the HOA board", phase: "launch", repeats: ""}}
      expect(plan.tasks.where(title: "Call the HOA board", repeats: nil)).to exist

      get google_ads_plan_path(plan)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Before you build", "Call the HOA board", "No goal", "Landing page /nowhere isn&#39;t a page on this site", "Download for Ads Editor")

      get edit_google_ads_plan_path(plan)
      expect(response.body).to include("Presence: people in or regularly in your locations")

      delete google_ads_plan_path(plan)
      expect(GoogleAds::Plan.count).to eq(0)
    end

    it "says an ad group isn't valid" do
      plan = GoogleAds::Plan.create!(name: "P")
      post google_ads_plan_ad_groups_path(plan), params: {ad_group: {name: "", path1: "a" * 20}}
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
