# デフォルトユーザー
user = User.find_or_create_by!(email: 'takaya314boxing@gmail.com') do |u|
  u.password = 'Takaya314!'
  u.name = '西野 鷹也'
end
puts "✅ Default user: #{user.email}"

# 未紐付けデータをユーザーに紐付け
Item.where(user_id: nil).update_all(user_id: user.id)
ServiceConnection.where(user_id: nil).update_all(user_id: user.id)
puts "✅ Existing data associated with #{user.email}"
