# frozen_string_literal: true

# schema.rb は本番 MySQL（JawsDB）から dump された形式で `size: :medium/:long` を含むため、
# sqlite のテスト DB で読むとエラーになる。
# schema.rb を sqlite 形式に書き換えるのは本番との乖離を生むので、読み側で吸収する。
#
# 列オプションの検証（abstract/schema_definitions.rb の create_column_definition が
# valid_column_definition_options に対して assert_valid_keys を行う）で、
# sqlite の TableDefinition に限り :size を許可する。sqlite は :size を使わず無視するため、
# 読み飛ばすのと同じ結果になる。test 環境のみ有効。
if Rails.env.test?
  module SqliteSchemaSizeOptionCompatibility
    private

    def valid_column_definition_options
      super + [:size]
    end
  end

  ActiveSupport.on_load(:active_record_sqlite3adapter) do
    ActiveRecord::ConnectionAdapters::SQLite3::TableDefinition.prepend(SqliteSchemaSizeOptionCompatibility)
  end
end
