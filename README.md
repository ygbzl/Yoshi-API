# README

This is my first Rails project.
It is a restful API that takes a latitue and longitude as params and will return a json with current location and nearest gas station information as response.

* version
	Rails 5.1.4
	Ruby 2.3.3

# dependencies
	Gem: 'rest-client'	used for make requests to 3rd party API
		 'rspec-rails'	used for write test case

	3rd party API:
		Google place API: https://developers.google.com/places/web-service/search
			Place Search: https://maps.googleapis.com/maps/api/place/nearbysearch/output?parameters
			used for query a place_id by Latitude and longitude

			Place Details: https://maps.googleapis.com/maps/api/place/details/output?parameters
			used for query detailed address information by place_id

		US Street Address API: https://smartystreets.com/products/apis/us-street-api
			used for query ZIP+4 codes
			note: Because Google API does not provide zip+4 code, I have to rely on this API to meet the requirement. However, this API only has 250 free quota per month. USPS API can also provide this service as we follow the policies.

	Database: sqlite3

# How to Run/Test
	Run 'bundle install' and 'rails db:migrate', then can run the server by 'rails server'
	For test, first run 'rails db:migrate RAILS_ENV=test', then can run the Rspec by 'bundle exec rspec'

* How to Use
	Once the server is running, the server can accpect a request with a latitude and longitude like this:

		GET localhost:3000/nearest_gas?lat=35.939467&lng=-86.656045

	It will return a json with http status '200':
	{
      address: {
        streetAddress: '2501 York Road',
        city: 'Nolensville',
        state: 'TN',
        postalCode: '37135-9790'
      },
      nearest_gas_station: {
        streetAddress: '910 Oldham Drive',
        city: 'Nolensville',
        state: 'TN',
        postalCode: '37135-9454'
      }
    }

    If the params latitude and longitude is lack, or is not a numeric, or is out of range, or there is no street in that location, then the server will return an error response with status code '400'.
    If the params is valid but there is no gas station nearby, then response with status code '204'
    You can see the input case in spec/requests/nearest_gas_spec.rb

* Server Logic and Cache Strategy 
	params: In the format of latitude and longitude, I noticed that 0.0001 equals around 10 meters. Assumed that two locations within 10 meters (actually it's 14.14 meters at most) shared the same addres information, I stored 4 digits (or less) decimal as instance value:
		lat = 35.939467    >> @lat = 35.9395
		lng = -86.656045   >> @lng = -86.656
	By doing this, the server can treat two near request as the same one.

	database schema:
		Location table: lat: float, lng: float, placeId: string
		Zip4 table	  :	place_id: string, zip4_code: string

	cache schema: I use the rails implemented Low-Level Caching with memory store, by the methode Rails.cache.fetch.
		First Cache:
			key: "#{@lat},#{@lng}", value: the final json result, expires_in: 30 days
		Second Cache:
			Key: current place id, value: the json result of nearest gas station, expires_in: 30 days
			Key: gas station place id, value: the json result of nearest gas station, expires_in: 30 days

			(current place id is the place_id queried from Google API by @lat and @lng, and the gas station place id is the nearest gas station, the value is the second part of the final json result, 'nearest_gas_station'. Actually these are two schema with the same format)

	cache strategy:
		with the above database schema and cache schema, once the server gets @lat and @lng, the cache strategy is implemented in this way:

			1. Check in First Cache, if cache hit, return the cache value
			if cache miss, then:

				2. Check in Location table, if there exists an entry, get the cur_id (current place id),
				if not exist, query from Google API to get the cur_id, and store into the database. 
				(note:for the current place id, I did not implement approximate search, that means for each different pair of @lat, @lng, at least one request is sent to Google API and will be store in the database. The reason I do this way is that I noticed even two location differ by 0.0001 like (@lat = 37.778, @lng = -122.4119) and (@lat = 37.778, @lng = -122.4120) can have different street number).
				get the current address information by query to Google API with cur_id.

				3. Check repeated current place id. Once get cur_id, search other entries with the same cur_id in Location table. Check First Cache again by these entries's lat and lng. Example:

					entry1 lat = 37.778, lng = -122.4119, placeId = "abcd"
					entry2 lat = 37.778, lng = -122.4118, placeId = "abcd"

					entry1 is what we are dealing with now, we find the entry2, then check in First Cache to see if '37.778,-122.4118' is cached.
					(note: I am not sure if this step is necessary, because this may cost more time on database query)

				4. Get the nearest gas station place_id. First do approximate search in Location table to find a place_id within 100 meters, then check Second Cache, example:

					entry1 lat = 37.778, lng = -122.4119, placeId = "abcd111"
					entry2 lat = 37.7785, lng = -122.4129, placeId = "abcd222"

					entry1 is the current location, by approximate search (0.001 difference in lat or lng, about 100 meters), we get the entry2, then check Second Cache with 'abcd222'.

				If Second Cache hit, then all the json result is got as we have current location information and nearest gas station information.
				If cache miss, then query from Google API 





