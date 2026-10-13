# frozen_string_literal: true

module GoogleAds
  # A plan's ad groups.
  class PlanAdGroupsController < ApplicationController
    requires_capability "google_ads:plan", only: [:new, :create, :edit, :update, :destroy]

    before_action :set_plan
    before_action :set_ad_group, only: [:edit, :update, :destroy]

    def new
      @ad_group = @plan.ad_groups.build
    end

    def create
      @ad_group = @plan.ad_groups.build(ad_group_params)
      if @ad_group.save
        redirect_to google_ads_plan_path(@plan, anchor: "ad-groups"), notice: "“#{@ad_group.name}” added"
      else
        render :new, status: :unprocessable_content
      end
    end

    def edit
    end

    def update
      if @ad_group.update(ad_group_params)
        redirect_to google_ads_plan_path(@plan, anchor: "ad-groups"), notice: "Saved"
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      @ad_group.destroy!
      redirect_to google_ads_plan_path(@plan, anchor: "ad-groups"), notice: "“#{@ad_group.name}” removed"
    end

    private

    def set_ad_group
      @ad_group = @plan.ad_groups.find(params[:id])
    end

    def ad_group_params
      params.require(:ad_group).permit(:name, :landing_path, :keywords, :headlines, :descriptions, :path1, :path2, :notes)
    end
  end
end
