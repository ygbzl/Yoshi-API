class CreateLocations < ActiveRecord::Migration[5.1]
  def change
    create_table :locations do |t|
      t.float :lat
      t.float :lng
      t.string :placeId

      t.timestamps
    end
  end
end
