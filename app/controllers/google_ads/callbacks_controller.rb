# frozen_string_literal: true

module GoogleAds
  # Where Google sends the person back after signing in: the code exchanged
  # for a refresh token, then the ad accounts it reaches loaded to pick from.
  class CallbacksController < ::Settings::BaseController
    include PluginGated
    plugin :google_ads

    requires_capability "settings:write", only: :show

    def show
      state = session.delete(:google_ads_oauth_state)
      return redirect_to(settings_google_ads_path, alert: "Google said: #{params[:error].to_s.humanize}") if params[:error].present?
      return redirect_to(settings_google_ads_path, alert: "That sign-in didn't start here; connect again") if state.blank? || !ActiveSupport::SecurityUtils.secure_compare(state, params[:state].to_s)

      answer = GoogleAds::Client.new.exchange(code: params.require(:code), redirect_uri: settings_google_ads_callback_url)
      GoogleAds::Settings.connect(**answer)
      Event.record("settings.google_ads_connected")
      notice = "Connected as #{answer[:email] || "your Google account"}"
      begin
        GoogleAds::Accounts.load
      rescue GoogleAds::Error => error
        notice += ". The ad accounts couldn't load: #{error.message}"
      end
      redirect_to settings_google_ads_path, notice: notice
    rescue GoogleAds::Error => error
      redirect_to settings_google_ads_path, alert: error.message
    end
  end
end
