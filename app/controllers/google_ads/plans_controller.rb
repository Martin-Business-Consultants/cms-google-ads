# frozen_string_literal: true

module GoogleAds
  # Campaign plans: the list, one plan with its checks and checklist, making
  # and changing one, the Ads Editor download, and applying its negatives.
  class PlansController < ApplicationController
    requires_capability "google_ads:read", only: [:index, :show, :export]
    requires_capability "google_ads:plan", only: [:new, :create, :edit, :update, :destroy]
    requires_capability "google_ads:write", only: [:apply_negatives, :attach_exclusions]

    before_action :set_plan, only: [:show, :edit, :update, :destroy, :export, :apply_negatives, :attach_exclusions]

    def index
      @plans = GoogleAds::Plan.ordered.includes(:tasks, :ad_groups).to_a
    end

    def show
      @guide = GoogleAds::Guide::Progress.new(@plan)
      @live = GoogleAds::PlanLive.for(@plan)
      @checks = GoogleAds::PlanChecks.new(@plan, live: @live)
    end

    def new
      @plan = GoogleAds::Plan.new(networks: "search", status: "planning")
    end

    def create
      @plan = GoogleAds::Plan.from_template(plan_params, template: params[:template])
      if @plan.save
        Event.record("google_ads.plan_created", plan_id: @plan.id)
        redirect_to google_ads_plan_guide_path(@plan), notice: "Plan made. The guide takes it from here, a step at a time."
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @plan.update(plan_params)
        redirect_to google_ads_plan_path(@plan), notice: "Saved"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @plan.destroy!
      Event.record("google_ads.plan_deleted", name: @plan.name)
      redirect_to google_ads_plans_path, notice: "“#{@plan.name}” deleted"
    end

    def export
      export = GoogleAds::PlanExport.new(@plan, site_url: Setting.get("general")["site_base_url"].presence || request.base_url)
      send_data export.to_csv, filename: export.filename, type: "text/csv"
    end

    def apply_negatives
      answer = GoogleAds::Changes.new.apply_plan_negatives(@plan)
      message = answer[:added].any? ? "Added #{answer[:added].size} negative#{"s" if answer[:added].size > 1} to the campaign" : "Nothing to add: the campaign has them all"
      redirect_to google_ads_plan_path(@plan), (answer[:failed] ? :alert : :notice) => [message, answer[:failed]].compact.join(". ")
    rescue GoogleAds::Error => error
      redirect_to google_ads_plan_path(@plan), alert: error.message
    end

    def attach_exclusions
      answer = GoogleAds::Changes.new.attach_exclusion_lists(@plan)
      redirect_to back_or_plan, notice: "Exclusion lists synced#{", and #{answer[:attached].size} attached to the campaign" if answer[:attached].any?}"
    rescue GoogleAds::Error => error
      redirect_to back_or_plan, alert: error.message
    end

    private

    def back_or_plan = params[:back].to_s.start_with?("/") && !params[:back].to_s.start_with?("//") ? params[:back] : google_ads_plan_path(@plan)

    def plan_params
      params.require(:plan).permit(:name, :status, :goal, :success, :audience, :daily_budget, :starts_on, :decision_on, :locations, :schedule,
        :bidding, :networks, :final_url_suffix, :campaign_id, :negatives, :notes)
    end
  end
end
