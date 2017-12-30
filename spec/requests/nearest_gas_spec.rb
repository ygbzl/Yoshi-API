require 'rails_helper'

RSpec.describe 'NearestGas API', type: :request do

  before :all do
    @lat = 35.939467
    @lng = -86.656045
    @valid_response = {
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
    }.to_json
  end

  describe 'edge case input test' do
    context 'input valid location: 35.939467, -86.656045' do
      it 'should response a valid json' do
        get 'http://localhost:3000/nearest_gas', params: { lat: @lat, lng: @lng }
        expect(JSON.parse(response.body)).to eq(JSON.parse(@valid_response))
      end
    end
    context 'lack of params' do
      it 'should response 400' do
        get 'http://localhost:3000/nearest_gas', params: { lng: @lng }
        expect(response).to have_http_status(400)

        get 'http://localhost:3000/nearest_gas', params: { lat: @lat }
        expect(response).to have_http_status(400)

        get 'http://localhost:3000/nearest_gas'
        expect(response).to have_http_status(400)
      end
    end
    context 'invalid input (not numeric)' do
      it 'should response 400' do
        get 'http://localhost:3000/nearest_gas', params: { lat: "#{@lat}asd", lng: @lng }
        expect(response).to have_http_status(400)

        get 'http://localhost:3000/nearest_gas', params: { lat: "random", lng: @lng }
        expect(response).to have_http_status(400)
      end
    end

    context 'input out of range' do
      it 'should response 400' do
        get 'http://localhost:3000/nearest_gas', params: { lat: 111111, lng: @lng }
        expect(response).to have_http_status(400)
      end
    end
  end

  describe 'cache check' do
    let(:memory_store) { ActiveSupport::Cache.lookup_store(:memory_store) }
    let(:cache) { Rails.cache }

    before do
      allow(Rails).to receive(:cache).and_return(memory_store)
      Rails.cache.clear
    end

    it 'should have two kinds of cache entry with @lat and @lng' do
      get 'http://localhost:3000/nearest_gas', params: { lat: @lat, lng: @lng }
      temp1 = @lat.to_f.round(4)
      temp2 = @lng.to_f.round(4)
      place_id = 'ChIJ9wwgXR50ZIgRxidB4lNPjzQ'
      expect(cache.exist?("#{temp1},#{temp2}")).to be(true)
      expect(cache.exist?("#{place_id}")).to be(true)
    end
  end
end
