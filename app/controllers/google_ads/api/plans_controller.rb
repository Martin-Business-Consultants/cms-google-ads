# frozen_string_literal: true

module GoogleAds
  module Api
    # /api/google_ads/plans: campaign plans, with their checks, the live
    # campaign beside them, the Ads Editor CSV, and applying their negatives.
    class PlansController < BaseController
      PLAN_FIELDS = %i[name status goal success audience daily_budget starts_on decision_on locations schedule bidding networks
        final_url_suffix campaign_id negatives notes].freeze
      AD_GROUP_FIELDS = %i[name landing_path keywords headlines descriptions path1 path2 notes].freeze

      requires_capability "google_ads:read", only: [:index, :show, :export]
      requires_capability "google_ads:plan", only: [:create, :update, :destroy]
      requires_capability "google_ads:write", only: :negatives

      before_action :set_plan, only: [:show, :update, :destroy, :export, :negatives]

      def index
        plans = GoogleAds::Plan.ordered.includes(:tasks, :ad_groups)
        render json: {plans: plans.map { it.as_json.slice(:id, :name, :status, :daily_budget, :starts_on, :decision_on, :days_to_decision, :campaign_id, :progress, :updated_at) }}
      end

      def show
        live = GoogleAds::PlanLive.for(@plan, settings: settings)
        render json: {**@plan.as_json, checks: GoogleAds::PlanChecks.new(@plan, live: live).results,
                      live: live && {campaign: live.campaign, negatives_on_campaign: live.negatives.size, missing_negatives: live.missing_negatives, error: live.error}}
      end

      # {plan: {...fields, ad_groups: [{...}]}, template: "search_leads"|"blank"}; keywords, headlines and
      # descriptions are text, one a line, or arrays.
      def create
        plan = GoogleAds::Plan.from_template(plan_params, template: params[:template])
        Array(params.dig(:plan, :ad_groups)).each { plan.ad_groups.build(ad_group_attributes(it)) }
        plan.save!
        Event.record("google_ads.plan_created", plan_id: plan.id)
        render json: plan.as_json, status: :created
      end

      def update
        @plan.update!(plan_params)
        render json: @plan.as_json
      end

      def destroy
        @plan.destroy!
        render json: {deleted: @plan.id}
      end

      def export
        export = GoogleAds::PlanExport.new(@plan, site_url: Setting.get("general")["site_base_url"].presence || request.base_url)
        send_data export.to_csv, filename: export.filename, type: "text/csv"
      end

      # POST {validate_only}: the plan's negatives the campaign doesn't have yet, added.
      def negatives
        report # the readiness check
        render json: GoogleAds::Changes.new(settings: settings).apply_plan_negatives(@plan, validate_only: validate_only?)
      end

      private

      def set_plan
        @plan = GoogleAds::Plan.find(params[:id])
      end

      def plan_params
        attributes = params.require(:plan).permit(*PLAN_FIELDS, negatives: [])
        attributes[:negatives] = attributes[:negatives].join("\n") if attributes[:negatives].is_a?(Array)
        attributes
      end

      def ad_group_attributes(group)
        self.class.lines(ActionController::Parameters.new(group.respond_to?(:to_unsafe_h) ? group.to_unsafe_h : group)
          .permit(*AD_GROUP_FIELDS, keywords: [], headlines: [], descriptions: []))
      end

      def self.lines(attributes)
        %i[keywords headlines descriptions].each { attributes[it] = attributes[it].join("\n") if attributes[it].is_a?(Array) }
        attributes
      end
    end
  end
end
