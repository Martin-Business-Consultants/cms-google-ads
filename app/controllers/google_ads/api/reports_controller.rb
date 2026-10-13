# frozen_string_literal: true

module GoogleAds
  module Api
    # GET /api/google_ads/{daily,campaigns,search_terms,keywords,conversion_actions}.
    class ReportsController < BaseController
      requires_capability "google_ads:read", only: [:daily, :campaigns, :search_terms, :keywords, :conversion_actions]

      def daily = render(json: {period: period, days: report.daily(range)})

      def campaigns = render(json: {period: period, campaigns: report.campaigns(range)})

      def search_terms
        render json: {period: period, search_terms: report.search_terms(range, campaign_id: params[:campaign_id], limit: params[:limit].presence || 100)}
      end

      def keywords = render(json: {period: period, keywords: report.keywords(range)})

      def conversion_actions = render(json: {conversion_actions: report.conversion_actions})
    end
  end
end
