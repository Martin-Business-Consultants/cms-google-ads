# frozen_string_literal: true

module GoogleAds
  module Api
    # /api/google_ads/plans/:plan_id/tasks: the checklist. PATCH {done: true|false} ticks one.
    class PlanTasksController < BaseController
      requires_capability "google_ads:plan", only: [:create, :update, :destroy]

      before_action { @plan = GoogleAds::Plan.find(params[:plan_id]) }

      def create
        task = @plan.tasks.create!(params.require(:task).permit(:phase, :title, :hint, :repeats))
        render json: task.as_json, status: :created
      end

      def update
        task = @plan.tasks.find(params[:id])
        task.update!(params.fetch(:task, {}).permit(:title, :hint, :phase, :repeats)) if params[:task].present?
        if params.key?(:done) && ActiveModel::Type::Boolean.new.cast(params[:done]) != task.done?
          task.toggle!(by: Current.user&.name.presence || Current.user&.email)
        end
        render json: task.as_json
      end

      def destroy
        @plan.tasks.find(params[:id]).destroy!
        render json: {deleted: params[:id].to_i}
      end
    end
  end
end
