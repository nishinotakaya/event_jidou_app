class Users::SessionsController < ActionController::Base
  # Deviseのデフォルトセッション処理をオーバーライド
  # API経由のログインは Api::SessionsController#login を使う
end
