# frozen_string_literal: true

module GoogleAds
  # Exclusion lists: negative keywords kept once by theme, synced to Google
  # Ads as shared negative keyword lists.
  class ExclusionListsController < ApplicationController
    requires_capability "google_ads:read", only: :index
    requires_capability "google_ads:plan", only: [:new, :create, :edit, :update, :destroy]
    requires_capability "google_ads:write", only: :sync

    before_action :set_list, only: [:edit, :update, :destroy, :sync]

    def index
      @lists = GoogleAds::ExclusionList.ordered.to_a
      @ready = GoogleAds::Settings.current.ready?
    end

    def new
      @list = GoogleAds::ExclusionList.new
    end

    def create
      @list = GoogleAds::ExclusionList.new(list_params)
      if @list.save
        redirect_to back_path, notice: "“#{@list.name}” added"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @list.update(list_params)
        redirect_to back_path, notice: "Saved#{". Sync it to update Google Ads" if @list.shared_set_id}"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @list.destroy!
      GoogleAds::Plan.find_each { |plan| plan.update_column(:exclusion_list_ids, Array(plan.exclusion_list_ids) - [@list.id]) if Array(plan.exclusion_list_ids).include?(@list.id) }
      redirect_to google_ads_exclusion_lists_path, notice: "“#{@list.name}” deleted here#{"; it stays in Google Ads until removed there" if @list.shared_set_id}"
    end

    def sync
      answer = GoogleAds::Changes.new.sync_exclusion_list(@list)
      redirect_to google_ads_exclusion_lists_path, notice: "“#{@list.name}” is in Google Ads: #{answer[:added].size} added, #{answer[:removed].size} removed"
    rescue GoogleAds::Error => error
      redirect_to google_ads_exclusion_lists_path, alert: error.message
    end

    private

    def set_list
      @list = GoogleAds::ExclusionList.find(params[:id])
    end

    def list_params = params.require(:exclusion_list).permit(:name, :description, :keywords)

    def back_path = params[:back].to_s.start_with?("/") && !params[:back].to_s.start_with?("//") ? params[:back] : google_ads_exclusion_lists_path
  end
end
