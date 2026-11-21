class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :uid
      t.string :email
      t.string :first_name
      t.string :last_name
      t.string :provider

      t.timestamps
    end

    add_index :users, [:provider, :uid], unique: true
    add_index :users, :email
  end
end
