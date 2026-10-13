# frozen_string_literal: true

module GoogleAds
  module Api
    # The changes it can make (GoogleAds::Changes), each with validate_only to dry-run.
    class ChangesController < BaseController
      requires_capability "google_ads:write", only: [:negative_keywords, :campaign, :conversions]

      # POST /api/google_ads/negative_keywords {campaign_id, keywords: [...], match_type, validate_only}
      def negative_keywords
        render json: changes.negative_keywords(campaign_id: params.require(:campaign_id), keywords: params.require(:keywords),
          match_type: params[:match_type], validate_only: validate_only?)
      end

      # PATCH /api/google_ads/campaigns/:id {status: PAUSED|ENABLED, validate_only}
      def campaign
        render json: changes.campaign_status(campaign_id: params[:id], status: params.require(:status), validate_only: validate_only?)
      end

      # POST /api/google_ads/conversions {gclid, conversion_action_id, at, value, currency, validate_only}
      def conversions
        render json: changes.upload_conversion(gclid: params.require(:gclid), conversion_action_id: params.require(:conversion_action_id),
          at: params[:at], value: params[:value], currency: params[:currency], validate_only: validate_only?)
      end

      private

      def changes
        report # the same readiness check
        GoogleAds::Changes.new(settings: settings)
      end
    end
  end
end
