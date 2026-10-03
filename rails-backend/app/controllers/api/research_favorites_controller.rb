module Api
  # 交流会リサーチのお気に入り（星）。ユーザーごとに、イベントURLで一意。
  #
  # 星を付けた時点の表示内容（タイトル・日時・会場…）ごと保存する。
  # 検索結果は毎回サイトから取り直すので、保存しておかないと
  # 「掲載が終わった」「別のキーワードだと出てこない」だけで一覧から消えてしまうため。
  class ResearchFavoritesController < ApplicationController
    def index
      render json: { results: current_user.research_favorites.upcoming_first.map(&:to_result) }
    end

    # 同じURLを2回星付けしても失敗させず、最新の表示内容で上書きする（連打・再検索対策）。
    def create
      favorite = current_user.research_favorites.find_or_initialize_by(url: params[:url].to_s)
      favorite.assign_attributes(favorite_attributes)
      favorite.save!
      render json: favorite.to_result, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end

    def destroy
      current_user.research_favorites.find_by(url: params[:url].to_s)&.destroy
      render json: { ok: true }
    end

    private

    # フロントは検索結果の Hash をそのまま投げてくるので、camelCase を列名に写す。
    def favorite_attributes
      {
        site: params[:site],
        site_label: params[:siteLabel],
        title: params[:title],
        starts_at: params[:startsAt],
        datetime_text: params[:datetimeText],
        venue: params[:venue],
        address: params[:address],
        organizer: params[:organizer],
        participants: params[:participants],
        capacity: params[:capacity],
        image_url: params[:imageUrl]
      }
    end
  end
end
