# デフォルトユーザー
user = User.find_or_create_by!(email: 'takaya314boxing@gmail.com') do |u|
  u.password = 'Takaya314!'
  u.name = '西野 鷹也'
end
puts "Default user: #{user.email} (id: #{user.id})"

# 未紐付けデータをユーザーに紐付け
items_count = Item.where(user_id: nil).update_all(user_id: user.id)
folders_count = Folder.where(user_id: nil).update_all(user_id: user.id)
sc_count = ServiceConnection.where(user_id: nil).update_all(user_id: user.id)
puts "Associated: #{items_count} items, #{folders_count} folders, #{sc_count} connections"
