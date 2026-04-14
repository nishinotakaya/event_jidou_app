module Api
  class CommentsController < ApplicationController
    # GET /api/comments?item_id=xxx
    def index
      return render(json: []) unless params[:item_id].present?
      comments = EventComment.for_item(params[:item_id])
      render json: comments.map(&:as_json_safe)
    end

    # POST /api/comments
    def create
      comment = EventComment.new(
        item_id: params[:item_id],
        user_id: current_user&.id,
        user_name: current_user&.name || params[:user_name] || '匿名',
        body: params[:body],
      )
      if comment.save
        render json: comment.as_json_safe, status: :created
      else
        render json: { error: comment.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    # DELETE /api/comments/:id
    def destroy
      comment = EventComment.find(params[:id])
      comment.destroy!
      render json: { ok: true }
    end
  end
end
