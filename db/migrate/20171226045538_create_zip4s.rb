class CreateZip4s < ActiveRecord::Migration[5.1]
  def change
    create_table :zip4s do |t|
      t.string :place_id
      t.string :zip4_code

      t.timestamps
    end
  end
end
