# frozen_string_literal: true

module GoogleAds
  # Settings › Google Ads (GoogleAds::Settings).
  class SettingsController < ::Settings::BaseController
    include PluginGated
    plugin :google_ads

    requires_capability "settings:read", only: :show
    requires_capability "settings:write", only: :update

    def show
      @settings = GoogleAds::Settings.current
    end

    def update
      GoogleAds::Settings.update(params.require(:google_ads).permit(:client_id, :client_secret, :developer_token, :customer_id, :login_customer_id, :api_version))
      Event.record("settings.google_ads_updated")
      redirect_to settings_google_ads_path, notice: "Saved"
    end
  end
end
