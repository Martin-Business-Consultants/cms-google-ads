# frozen_string_literal: true

module GoogleAds
  module Api
    # GET|PATCH /api/google_ads/settings (the client secret, developer token and tokens are never read back).
    class SettingsController < BaseController
      requires_capability "settings:read", only: :show
      requires_capability "settings:write", only: :update

      def show
        render json: settings.to_h
      end

      def update
        updated = GoogleAds::Settings.update(params.require(:settings).permit(:client_id, :client_secret, :developer_token, :customer_id, :login_customer_id, :api_version))
        Event.record("settings.google_ads_updated")
        render json: updated.to_h
      end
    end
  end
end
