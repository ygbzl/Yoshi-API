class NearestGasController < ApplicationController
  # Note: here the Keys are just for demo
  # It should be maintained in a secret file
  # and add the file name in ".gitignore"
  KEY = "AIzaSyDvM_Fyh0ynMnpepAU57wmwmXlyVBYpFCs"
  ZIP_ID = "bee4b7b4-eabf-733a-dde3-f76ebe95a2dc"
  ZIP_TOKEN = "hg3LXw9o7OaDb12hJrV8"

  # stands for about 100 meters
  # used for approximate query
  RADIUS = 0.001

  # check if params are valid
  before_action :param_check, only: :show

  def show
    # if cached, just return
    unless (cached?)
      # find current location id
      set_cur_ID
      if (!@cur_id)
        # no place id found
        render plain:  'invalid request', status: 400
      else
        if(!check_repeat_id)
          # get current location information (json)
          @cur_inform = get_inform(@cur_id)

          # get gas station information
          @gas_inform = get_station_inform

          # render final result
          result = {"address" => @cur_inform, "nearest_gas_station" => @gas_inform}
          render json: result, status: @gas_inform == nil ? 204 : 200
          # store cache
          Rails.cache.fetch("#{@lat},#{@lng}", expire_in: 30.days) {result}
        end
      end
    end
  end

  private
    # As we get current location (A) id
    # search in the database to find another location (B) that has the same place id
    # If B is cached, than we can just response with B's result
    # because A and B share the same place_id, the result must be same
    # change the query range [0, 10] for performance  
    def check_repeat_id
      entry = Location.where(placeId: @cur_id)

      if(entry.size == 0)
        return false
      end

      # can loop for more, like 50 entries
      entry[0, 10].each do |data|
        cached = Rails.cache.fetch("#{data.lat},#{data.lng}")
        if(cached)
          render json: cached
          Rails.cache.fetch("#{@lat},#{@lng}", expires_in: 30.days) do
            cached
          end
          return true
        end
      end
      return false
    end

    # first do approximate search to check if other near location is cached
    #  near location within RADIUS, the gas station should be same
    # then query for detailed gas information
    def get_station_inform
      entry = Location.where(lat: @lat - RADIUS .. @lat + RADIUS, lng: @lng - RADIUS .. @lng + RADIUS)

      entry[0, 10].each do |data|
        cache = Rails.cache.fetch("#{data.placeId}")
        if(cache)
          return cache
        end
      end

      # query from Google API to get gas_id
      gas_id = get_station_id
      if (gas_id == nil)
        return nil
      end

      # check second cache
      cache2 = Rails.cache.fetch("#{gas_id}")
      if(cache2)
        # store cur_id for next approximate search
        Rails.cache.fetch("#{@cur_id}", expires_in: 30.days) do
          cache2
        end
        return cache2
      else
        gas_inform = get_inform(gas_id)
        # store cur_id for next approximate search
        Rails.cache.fetch("#{@cur_id}", expires_in: 30.days) do
          gas_inform
        end
        # store gas_id for next second cache check
        Rails.cache.fetch("#{gas_id}", expires_in: 30.days) do
          gas_inform
        end
        return gas_inform
      end
    end

    # query for the nearest gas station place id
    def get_station_id
      url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=#{@lat},#{@lng}&rankby=distance&types=gas_station&key=#{KEY}"
      begin
        response = JSON.parse(RestClient.get(url))
        gas_id = response["results"][0]["place_id"]
        return gas_id
      rescue
        return nil
      end
    end

    #get the detailed location information by place_id and parse it to a json
    def get_inform(place_id)
      url = "https://maps.googleapis.com/maps/api/place/details/json?placeid=#{place_id}&key=#{KEY}"
      response = JSON.parse(RestClient.get(url))
      if(response["status"] != "OK")
        return nil
      else
        inform = Hash.new
        response["result"]["address_components"].each do |component|
          if(component["types"].include? "street_number")
            inform["streetAddress"] = component["long_name"]
          end
          if(component["types"].include? "route")
            inform["streetAddress"] ||= ""
            inform["streetAddress"] << ' ' << component["long_name"]
          end
          if(component["types"].include? "locality")
            inform["city"] = component["long_name"]
          end
          if(component["types"].include? "administrative_area_level_1")
            inform["state"] = component["short_name"]
          end
          if(component["types"].include? "postal_code")
            inform["postalCode"] = component["long_name"]
          end
        end

        # get the zip4 code, add it to the inform
        append_zip(inform, place_id)
        return inform
      end
    end

    # get the 4-zip code, append it to the inform json
    # first search in the database
    # if not exist, then make a query to zip api
    def append_zip(inform, id)
      entry = Zip4.find_by(place_id: id)
      if (entry == nil)
        begin
          url = "https://us-street.api.smartystreets.com/street-address?auth-id=#{ZIP_ID}&auth-token=#{ZIP_TOKEN}&street=#{inform["streetAddress"]}&city=#{inform["city"]}&state=#{inform["state"]}"
          response = JSON.parse(RestClient.get(url))
          zip4 = response[0]["components"]["plus4_code"]
          inform["postalCode"] << '-' << zip4
        rescue
          zip4 = ''
        end
        Zip4.create(place_id: id, zip4_code: zip4)
      else
        if (entry.zip4_code == '')
          return
        else
          inform["postalCode"] << '-' << entry.zip4_code
        end
      end
    end

    # query from database to get ID
    # if not exist in database, then query form google api
    # set instance value @cur_id
    def set_cur_ID
      entry = Location.where(lat: @lat, lng: @lng)[0]
      if(entry.blank?)
        temp = getCurID(@lat, @lng)
        if(temp)
          @cur_id = temp
          Location.create(lat: @lat, lng: @lng, placeId: @cur_id)
        else
          @cur_id = nil
          Location.create(lat: @lat, lng: @lng)
        end
      else
        @cur_id = entry.placeId
      end
    end

    # check cache
    # if cached, fetch form cache and return result
    # else return false query by google_places Api to get an ID
    def cached?
      cached = Rails.cache.fetch("#{@lat},#{@lng}")
      unless (cached.nil?)
        render json:  cached
      else
        return false
      end
    end

    # send request to google api to get a place_id
    # if nil, then return false
    def getCurID(lat, lng)
      url = "https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=#{@lat},#{@lng}&rankby=distance&keyword=street&key=#{KEY}"
      response = JSON.parse(RestClient.get(url))
      if(response["status"] == "OK")
        id = response["results"][0]["place_id"]
        return id
      else
        return false
      end
    end

    # check is params exist
    # or is valid number
    # if valid, store params as instance value
    def param_check
      if(!is_number?(params[:lat]) || !is_number?(params[:lng]))
        render plain: "errs invalid params or lack of prams", status:400
      # if (params[:lat].blank? || params[:lng].blank?)
      #   # loss params, return 400
      #   render plain: "err lack of params", status:400
      else
        # nomorlize the format, keep 4 digits or less
        @lat = params[:lat].to_f.round(4)
        @lng = params[:lng].to_f.round(4)
      end
    end

    # check is num is valid float
    def is_number?(num)
      true if Float(num) rescue false
    end
end
