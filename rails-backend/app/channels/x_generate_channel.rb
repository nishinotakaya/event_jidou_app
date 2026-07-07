class XGenerateChannel < ApplicationCable::Channel
  def subscribed
    stream_from "x_generate_#{params[:job_id]}"
  end

  def unsubscribed
    stop_all_streams
  end
end
