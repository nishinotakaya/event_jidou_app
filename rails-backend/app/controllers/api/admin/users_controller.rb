module Api
  module Admin
    class UsersController < ApplicationController
      before_action :authorize_admin!

      # GET /api/admin/users
      def index
        users = User.order(:role, :email)
        render json: users.map { |u|
          {
            id: u.id,
            email: u.email,
            name: u.name,
            role: u.role,
            provider: u.provider,
            avatarUrl: u.avatar_url,
            lastSignInAt: u.updated_at&.iso8601,
            invitedById: u.invited_by_id,
            invitationAcceptedAt: u.invitation_accepted_at&.iso8601,
          }
        }
      end

      # POST /api/admin/users/invite
      def invite
        email = params[:email].to_s.strip.downcase
        role = params[:role].to_s.presence || 'viewer'

        return render json: { error: 'メールアドレスを入力してください' }, status: :bad_request if email.blank?
        return render json: { error: '無効なロールです' }, status: :bad_request unless User::ROLES.include?(role)
        return render json: { error: 'このメールアドレスは既に登録されています' }, status: :conflict if User.exists?(email: email)

        temp_password = SecureRandom.alphanumeric(12)
        token = SecureRandom.hex(20)

        user = User.new(
          email: email,
          password: temp_password,
          password_confirmation: temp_password,
          name: email.split('@').first,
          role: role,
          invited_by_id: current_user.id,
          invitation_token: token,
          invitation_sent_at: Time.current,
        )

        if user.save
          render json: {
            ok: true,
            user: { id: user.id, email: user.email, role: user.role },
            tempPassword: temp_password,
            invitationToken: token,
          }
        else
          render json: { error: user.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end
      end

      # PUT /api/admin/users/:id
      def update
        user = User.find(params[:id])
        return render json: { error: '自分のロールは変更できません' }, status: :forbidden if user.id == current_user.id

        if params[:role].present? && User::ROLES.include?(params[:role])
          user.update!(role: params[:role])
        end
        if params[:name].present?
          user.update!(name: params[:name])
        end

        render json: { ok: true, role: user.role }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'ユーザーが見つかりません' }, status: :not_found
      end

      # DELETE /api/admin/users/:id
      def destroy
        user = User.find(params[:id])
        return render json: { error: '自分は削除できません' }, status: :forbidden if user.id == current_user.id

        user.destroy!
        render json: { ok: true }
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'ユーザーが見つかりません' }, status: :not_found
      end
    end
  end
end
