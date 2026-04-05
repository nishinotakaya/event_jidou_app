module Api
  class CalendarController < ApplicationController
    before_action :require_user

    # GET /api/calendar/events?start=2026-04-01&end=2026-04-30
    def events
      time_min = Time.zone.parse(params[:start] || Date.current.beginning_of_month.to_s)
      time_max = Time.zone.parse(params[:end] || Date.current.end_of_month.to_s) + 1.day

      service = GoogleCalendarService.new(current_user)
      events = service.list_events(time_min: time_min, time_max: time_max)
      render json: { events: events }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # POST /api/calendar/events
    def create_event
      service = GoogleCalendarService.new(current_user)
      event = service.create_event(
        title: params[:title],
        description: params[:description] || '',
        start_time: params[:start_time],
        end_time: params[:end_time],
        location: params[:location],
      )
      render json: { event: event }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # PUT /api/calendar/events/:event_id
    def update_event
      service = GoogleCalendarService.new(current_user)
      event = service.update_event(
        params[:event_id],
        title: params[:title],
        start_time: params[:start_time],
        end_time: params[:end_time],
      )
      render json: { event: event }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    # DELETE /api/calendar/events/:event_id
    def delete_event
      service = GoogleCalendarService.new(current_user)
      service.delete_event(params[:event_id])
      render json: { ok: true }
    rescue => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def require_user
      unless current_user
        render json: { error: 'ログインが必要です' }, status: :unauthorized
      end
    end
  end
end
