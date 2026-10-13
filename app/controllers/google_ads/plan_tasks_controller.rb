# frozen_string_literal: true

module GoogleAds
  # A plan's checklist: ticking a task (or unticking it), adding one, removing one.
  class PlanTasksController < ApplicationController
    requires_capability "google_ads:plan", only: [:create, :update, :destroy]

    before_action :set_plan
    before_action :set_task, only: [:update, :destroy]

    def create
      task = @plan.tasks.build(params.require(:task).permit(:phase, :title, :hint, :repeats).merge(repeats: params.dig(:task, :repeats).presence))
      if task.save
        redirect_to google_ads_plan_path(@plan, anchor: "phase-#{task.phase}"), notice: "Added to the checklist"
      else
        redirect_to google_ads_plan_path(@plan, anchor: "checklist"), alert: task.errors.full_messages.to_sentence
      end
    end

    def update
      @task.toggle!(by: Current.user.name.presence || Current.user.email)
      redirect_to google_ads_plan_path(@plan, anchor: "phase-#{@task.phase}")
    end

    def destroy
      @task.destroy!
      redirect_to google_ads_plan_path(@plan, anchor: "phase-#{@task.phase}"), notice: "Removed from the checklist"
    end

    private

    def set_task
      @task = @plan.tasks.find(params[:id])
    end
  end
end
