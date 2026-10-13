# frozen_string_literal: true

module GoogleAds
  # A search term from the Google Ads page added to its campaign as a phrase-match negative.
  class NegativeKeywordsController < ApplicationController
    include PluginGated
    plugin :google_ads

    requires_capability "google_ads:write", only: :create

    def create
      answer = GoogleAds::Changes.new.negative_keywords(campaign_id: params.require(:campaign_id), keywords: params.require(:keyword),
        match_type: params[:match_type].presence || "PHRASE")
      message = answer[:failed] || "“#{answer[:added].to_sentence}” won't show your ads in that campaign any more"
      redirect_to google_ads_report_path(days: params[:days].presence), (answer[:failed] ? :alert : :notice) => message
    rescue GoogleAds::Error => error
      redirect_to google_ads_report_path(days: params[:days].presence), alert: error.message
    end
  end
end
