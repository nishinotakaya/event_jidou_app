module Api
  class TextsController < ApplicationController
    before_action :authorize_editor!, only: [:create, :update, :destroy]

    def index
      # 全ユーザーのアイテムを閲覧可能（管理者のアイテムを共有）
      items = Item.where(item_type: params[:type]).order(:created_at)
      render json: items.map { |i| format_item(i) }
    end

    def create
      item = current_user.items.new(
        item_type:      params[:type],
        name:           item_params[:name],
        content:        item_params[:content],
        folder:         item_params[:folder] || '',
        event_date:     item_params[:eventDate],
        event_time:     item_params[:eventTime],
        event_end_time: item_params[:eventEndTime],
        zoom_url:       item_params[:zoomUrl],
        onclass_mentions:  params.key?(:onclassMentions) ? Array(params[:onclassMentions]).to_json : nil,
        onclass_channels:  params.key?(:onclassChannels) ? Array(params[:onclassChannels]).to_json : nil,
        student_post_type: params[:studentPostType],
      )
      if item.save
        render json: format_item(item)
      else
        render json: { error: item.errors.full_messages.join(', ') }, status: :unprocessable_entity
      end
    end

    def update
      item = Item.find_by(id: params[:id], item_type: params[:type])
      return render json: { error: 'Not found' }, status: :not_found unless item

      item.assign_attributes(
        name:    item_params[:name]    || item.name,
        content: item_params[:content] || item.content,
      )
      item.folder = item_params[:folder] if item_params.key?(:folder)
      item.event_date     = item_params[:eventDate]     if item_params.key?(:eventDate)
      item.event_time     = item_params[:eventTime]     if item_params.key?(:eventTime)
      item.event_end_time = item_params[:eventEndTime]  if item_params.key?(:eventEndTime)
      item.zoom_url       = item_params[:zoomUrl]        if item_params.key?(:zoomUrl)
      if params.key?(:onclassMentions)
        item.onclass_mentions = Array(params[:onclassMentions]).to_json
      end
      if params.key?(:onclassChannels)
        item.onclass_channels = Array(params[:onclassChannels]).to_json
      end
      item.student_post_type = params[:studentPostType] if params.key?(:studentPostType)
      item.updated_at = Time.current
      item.save!
      render json: format_item(item)
    end

    # POST /api/check_duplicate_event — 日時重複チェック
    def check_duplicate
      date = params[:eventDate]
      time = params[:eventTime]
      exclude_id = params[:excludeId]

      return render(json: { duplicate: false }) if date.blank?

      scope = current_user.items.where(item_type: 'event', event_date: date)
      scope = scope.where(event_time: time) if time.present?
      scope = scope.where.not(id: exclude_id) if exclude_id.present?

      if scope.exists?
        existing = scope.first
        render json: {
          duplicate: true,
          message: "同じ開催日時（#{date} #{time}）のイベント「#{existing.name}」が既に存在します",
          existingName: existing.name,
          existingId: existing.id,
        }
      else
        render json: { duplicate: false }
      end
    end

    def destroy
      item = Item.find_by(id: params[:id], item_type: params[:type])
      return render json: { error: 'Not found' }, status: :not_found unless item

      item.destroy
      render json: { ok: true }
    end

    private

    def item_params
      params.permit(:name, :content, :folder, :eventDate, :eventTime, :eventEndTime,
                    :zoomUrl, :studentPostType, onclassMentions: [], onclassChannels: [])
    end

    def format_item(item)
      h = {
        id:           item.id,
        name:         item.name,
        type:         item.item_type,
        content:      item.content,
        folder:       item.folder || '',
        eventDate:    item.event_date,
        eventTime:    item.event_time,
        eventEndTime: item.event_end_time,
        zoomUrl:      item.zoom_url,
        createdAt:    item.created_at&.strftime('%Y-%m-%d'),
        updatedAt:    item.updated_at&.strftime('%Y-%m-%d'),
      }
      if item.item_type == 'student'
        h[:onclassMentions]  = JSON.parse(item.onclass_mentions || '[]') rescue []
        h[:onclassChannels]  = JSON.parse(item.onclass_channels || '[]') rescue []
        h[:studentPostType]  = item.student_post_type || '受講生告知'
      end
      h
    end
  end
end
