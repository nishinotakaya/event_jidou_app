class CreateOnclassStudents < ActiveRecord::Migration[7.2]
  def change
    create_table :onclass_students do |t|
      t.string :name
      t.string :course
      t.datetime :fetched_at

      t.timestamps
    end
  end
end
