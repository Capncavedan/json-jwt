require 'spec_helper'

describe JSON::JWK::Set::Fetcher do
  describe JSON::JWK::Set::Fetcher::Cache do
    let(:something) { SecureRandom.hex(32) }

    it 'just execute givne block' do
      expect(
        subject.fetch('cache_key') do
          something
        end
      ).to eq something
    end
  end

  describe 'debugging feature' do
    after { JSON::JWK::Set::Fetcher.debugging = false }

    its(:logger) { should be_a Logger }
    its(:debugging?) { should == false }

    describe '.debug!' do
      before { JSON::JWK::Set::Fetcher.debug! }
      its(:debugging?) { should == true }
    end

    describe '.debug' do
      it 'should enable debugging within given block' do
        JSON::JWK::Set::Fetcher.debug do
          JSON::JWK::Set::Fetcher.debugging?.should == true
        end
        JSON::JWK::Set::Fetcher.debugging?.should == false
      end

      it 'should not force disable debugging' do
        JSON::JWK::Set::Fetcher.debug!
        JSON::JWK::Set::Fetcher.debug do
          JSON::JWK::Set::Fetcher.debugging?.should == true
        end
        JSON::JWK::Set::Fetcher.debugging?.should == true
      end
    end
  end

  describe '.http_client' do
    context 'with http_config' do
      before do
        JSON::JWK::Set::Fetcher.http_config do |config|
          config.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end
      end
      it 'should configure OpenIDConnect, SWD and Rack::OAuth2\'s http_client' do
        JSON::JWK::Set::Fetcher.http_client.ssl_config.verify_mode.should == OpenSSL::SSL::VERIFY_NONE
      end
    end
  end

  describe 'fetching feature' do
    class CustomCache
      JWKS_URI = 'https://idp.example.com/jwks'

      def fetch(kid)
        base_key = "json:jwk:set:#{OpenSSL::Digest::MD5.hexdigest JWKS_URI}"
        case kid
        when "#{base_key}:known"
          File.read(File.join(File.dirname(__FILE__), '../../../mock_response/jwks.json'))
        else
          yield
        end
      end
    end

    let(:jwks_uri) { CustomCache::JWKS_URI }

    describe '.cache' do
      subject { JSON::JWK::Set::Fetcher.cache }

      context 'as default' do
        it { should be_instance_of JSON::JWK::Set::Fetcher::Cache }
      end

      context 'when specified' do
        around do |example|
          JSON::JWK::Set::Fetcher.cache = CustomCache.new
          example.run
          JSON::JWK::Set::Fetcher.cache = JSON::JWK::Set::Fetcher::Cache.new
        end
        it { should be_instance_of CustomCache }
      end
    end

    describe '.fetch' do
      subject { JSON::JWK::Set::Fetcher.fetch jwks_uri, kid: kid }

      around do |example|
        JSON::JWK::Set::Fetcher.cache = CustomCache.new
        example.run
        JSON::JWK::Set::Fetcher.cache = JSON::JWK::Set::Fetcher::Cache.new
      end

      context 'when not cached' do
        let(:kid) { 'not_cached' }

        it "should request to jwks_uri" do
          expect do
            subject
          end.to request_to jwks_uri
        end

        context 'when unknown' do
          let(:kid) { 'unknown' }

          it "should not request to jwks_uri" do
            expect do
              mock_json :get, jwks_uri, 'jwks' do
                subject
              end
            end.to raise_error JSON::JWK::Set::KidNotFound
          end
        end
      end

      context 'when cached' do
        context 'when known' do
          let(:kid) { 'known' }

          it "should not request to jwks_uri" do
            expect do
              subject
            end.not_to request_to jwks_uri
          end

          it do
            should be_instance_of JSON::JWK
          end

          context 'when auto_detect disabled' do
            subject { JSON::JWK::Set::Fetcher.fetch jwks_uri, kid: kid, auto_detect: false }

            it do
              should be_instance_of JSON::JWK::Set
            end
          end
        end
      end
    end
  end
end
