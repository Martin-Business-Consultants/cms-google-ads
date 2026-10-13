# frozen_string_literal: true

module GoogleAds
  module Api
    # /api/google_ads/plans/:plan_id/ad_groups: keywords, headlines and descriptions as text (one a line) or arrays.
    class PlanAdGroupsController < BaseController
      requires_capability "google_ads:plan", only: [:create, :update, :destroy]

      before_action { @plan = GoogleAds::Plan.find(params[:plan_id]) }

      def create
        group = @plan.ad_groups.create!(attributes)
        render json: group.as_json, status: :created
      end

      def update
        group = @plan.ad_groups.find(params[:id])
        group.update!(attributes)
        render json: group.as_json
      end

      def destroy
        @plan.ad_groups.find(params[:id]).destroy!
        render json: {deleted: params[:id].to_i}
      end

      private

      def attributes
        PlansController.lines(params.require(:ad_group).permit(*PlansController::AD_GROUP_FIELDS, keywords: [], headlines: [], descriptions: []))
      end
    end
  end
end
