class CreateJoinTableApiKeysRubygems < ActiveRecord::Migration[6.1]
  def change
    create_join_table :api_keys, :rubygems do |t|
      t.index [:api_key_id, :rubygem_id], unique: true
    end
  end
end
