require 'spec_helper'
require 'uri'
require 'cgi'
require 'grapi'

describe Grapi::Client do
  before :each do
    @app_id = 'abc'
    @app_secret = 'xyz'
    @client = Grapi::Client.new(@app_id, @app_secret)
    @redirect_uri = 'http://test.com/cb'
  end

  describe "#authorize_url" do
    it "fails without a redirect uri" do
      lambda { @client.authorize_url }.should raise_exception(ArgumentError)
    end

    it "generates the authorize url correctly" do
      url = URI.parse(@client.authorize_url(:redirect_uri => @redirect_uri))
      query = CGI.parse(url.query)
      query['response_type'].first.should == 'code'
      query['redirect_uri'].first.should == @redirect_uri
      query['client_id'].first.should == @app_id
    end
  end

  describe "#fetch_access_token" do
    access_token_url = "#{Grapi::Client::BASE_URL}/oauth/access_token"

    it "fails without a redirect uri" do
      lambda do
        @client.fetch_access_token('code', {})
      end.should raise_exception(ArgumentError)
    end

    describe "with valid params" do
      it "calls correct method with correct args" do
        auth_code = 'fakecode'
        access_token = mock

        @client.instance_variable_get(:@access_token).should be_nil

        oauth_client = @client.instance_variable_get(:@oauth_client)
        oauth_client.auth_code.expects(:get_token).with { |code,options|
          code == auth_code && options[:redirect_uri] == @redirect_uri
        }

        @client.fetch_access_token(auth_code, {:redirect_uri => @redirect_uri})
      end

      it "sets @access_token" do
        access_token = mock

        oauth_client = @client.instance_variable_get(:@oauth_client)
        oauth_client.auth_code.expects(:get_token).returns(access_token)

        @client.instance_variable_get(:@access_token).should be_nil
        @client.fetch_access_token('code', {:redirect_uri => @redirect_uri})
        @client.instance_variable_get(:@access_token).should == access_token
      end
    end
  end

  describe "#access_token" do
    it "serializes access token correctly" do
      oauth_client = @client.instance_variable_get(:@oauth_client)
      token = OAuth2::AccessToken.new(oauth_client, 'TOKEN123')
      token.params[:scope] = 'a:1 b:2'
      @client.instance_variable_set(:@access_token, token)

      @client.access_token.should == 'TOKEN123 a:1 b:2'
    end

    it "returns nil when there's no token" do
      @client.access_token.should be_nil
    end
  end

  describe "#access_token=" do
    it "deserializes access token correctly" do
      @client.access_token = 'TOKEN123 a:1 b:2'
      token = @client.instance_variable_get(:@access_token)
      token.token.should == 'TOKEN123'
      token.params[:scope].should == 'a:1 b:2'
    end
  end

  describe "#api_get" do
    it "uses the correct path prefix" do
      @client.access_token = 'TOKEN123 a:1 b:2'
      token = @client.instance_variable_get(:@access_token)
      token.expects(:get).with { |path,opts| path =~ %r|/api/v1/test| }
      @client.api_get('/test')
    end
  end

  describe "#merchant" do
    it "looks up the correct merchant" do
      @client.access_token = 'TOKEN a manage_merchant:123 b'
      response = mock
      response.expects(:parsed)

      token = @client.instance_variable_get(:@access_token)
      merchant_url = '/api/v1/merchants/123'
      token.expects(:get).with { |p,o| p == merchant_url }.returns response

      Grapi::Merchant.stubs(:from_hash)

      @client.merchant
    end

    it "creates a Merchant object" do
      @client.access_token = 'TOKEN manage_merchant:123'
      response = mock
      response.expects(:parsed).returns({:name => 'test', :id => 123})

      token = @client.instance_variable_get(:@access_token)
      token.expects(:get).returns response

      merchant = @client.merchant
      merchant.should be_an_instance_of Grapi::Merchant
      merchant.id.should == 123
      merchant.name.should == 'test'
    end
  end
end