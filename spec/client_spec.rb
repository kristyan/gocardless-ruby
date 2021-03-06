require 'spec_helper'

describe GoCardless::Client do
  before :each do
    @app_id = 'abc'
    @app_secret = 'xyz'
    @redirect_uri = 'http://test.com/cb'
  end

  describe ".base_url" do
    it "returns the correct url for the production environment" do
      GoCardless.environment = :production
      GoCardless::Client.base_url.should == 'https://gocardless.com'
    end

    it "returns the correct url for the sandbox environment" do
      GoCardless.environment = :sandbox
      GoCardless::Client.base_url.should == 'https://sandbox.gocardless.com'
    end

    it "returns the correct url when it's set manually" do
      GoCardless::Client.base_url = 'https://abc.gocardless.com'
      GoCardless::Client.base_url.should == 'https://abc.gocardless.com'
    end
  end

  describe "#new" do
    it "without an app id should raise an error" do
      lambda do
        GoCardless::Client.new({:app_secret => @app_secret})
      end.should raise_exception(GoCardless::ClientError)
    end
    it "without an app_secret should raise an error" do
      lambda do
        GoCardless::Client.new({:app_id => @app_id})
      end.should raise_exception(GoCardless::ClientError)
    end
  end

  before do
    @client = GoCardless::Client.new({:app_id => @app_id, :app_secret => @app_secret})
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
    access_token_url = "#{GoCardless::Client.base_url}/oauth/access_token"

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
        oauth_client.auth_code.expects(:get_token).with(
          auth_code, has_entry(:redirect_uri => @redirect_uri)
        )

        @client.fetch_access_token(auth_code, {:redirect_uri => @redirect_uri})
      end

      it "sets @access_token" do
        access_token = mock
        access_token.stubs(:params).returns('scope' => '')
        access_token.stubs(:token).returns('')

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
      token.params['scope'] = 'a:1 b:2'
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
      token.params['scope'].should == 'a:1 b:2'
    end

    it "handles invalid values correctly" do
      token = 'TOKEN123'  # missing scope
      expect { @client.access_token = token }.to raise_exception ArgumentError
    end
  end

  describe "#api_get" do
    it "uses the correct path prefix" do
      @client.access_token = 'TOKEN123 a:1 b:2'
      token = @client.instance_variable_get(:@access_token)
      r = mock
      r.stubs(:parsed)
      token.expects(:get).with { |p,o| p =~ %r|/api/v1/test| }.returns(r)
      @client.api_get('/test')
    end

    it "fails without an access_token" do
      expect { @client.api_get '/' }.to raise_exception GoCardless::ClientError
    end
  end

  describe "#api_post" do
    it "encodes data to json" do
      @client.access_token = 'TOKEN123 a:1 b:2'
      token = @client.instance_variable_get(:@access_token)
      r = mock
      r.stubs(:parsed)
      token.expects(:post).with { |p,opts| opts[:body] == '{"a":1}' }.returns(r)
      @client.api_post('/test', {:a => 1})
    end

    it "fails without an access_token" do
      expect { @client.api_get '/' }.to raise_exception GoCardless::ClientError
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

      GoCardless::Merchant.stubs(:new_with_client)

      @client.merchant
    end

    it "creates a Merchant object" do
      @client.access_token = 'TOKEN manage_merchant:123'
      response = mock
      response.expects(:parsed).returns({:name => 'test', :id => 123})

      token = @client.instance_variable_get(:@access_token)
      token.expects(:get).returns response

      merchant = @client.merchant
      merchant.should be_an_instance_of GoCardless::Merchant
      merchant.id.should == 123
      merchant.name.should == 'test'
    end
  end

  %w{subscription pre_authorization user bill payment}.each do |resource|
    describe "##{resource}" do
      it "returns the correct #{GoCardless::Utils.camelize(resource)} object" do
        @client.access_token = 'TOKEN manage_merchant:123'
        stub_get(@client, {:id => 123})
        obj = @client.send(resource, 123)
        obj.should be_a GoCardless.const_get(GoCardless::Utils.camelize(resource))
        obj.id.should == 123
      end
    end
  end

  describe "#encode_params" do
    it "correctly encodes hashes" do
      params = {:a => {:b => :c}, :x => :y}
      result = 'a%5Bb%5D=c&x=y'
      @client.send(:encode_params, params).should == result
    end

    it "correctly encodes arrays" do
      params = {:a => [1,2]}
      result = 'a%5B%5D=1&a%5B%5D=2'
      @client.send(:encode_params, params).should == result
    end

    it "sorts params by key" do
      params = {:b => 1, :a => 2}
      result = 'a=2&b=1'
      @client.send(:encode_params, params).should == result
    end
  end

  it "#sign_params signs pararmeter hashes correctly" do
    @client.instance_variable_set(:@app_secret, 'testsecret')
    params = {:test => true}
    sig = '6e4613b729ce15c288f70e72463739feeb05fc0b89b55d248d7f259b5367148b'
    @client.send(:sign_params, params)[:signature].should == sig
  end

  describe "#signature_valid?" do
    before(:each) { @params = { :x => 'y', :a => 'b' } }

    it "succeeds with a valid signature" do
      params = @client.send(:sign_params, @params)
      @client.send(:signature_valid?, params).should be_true
    end

    it "fails with an invalid signature" do
      params = {:signature => 'invalid'}.merge(@params)
      @client.send(:signature_valid?, params).should be_false
    end
  end

  describe "#confirm_resource" do
    before :each do
      @params = {
        :resource_id   => '1',
        :resource_uri  => 'a',
        :resource_type => 'subscription',
      }
    end

    [:resource_id, :resource_uri, :resource_type].each do |param|
      it "fails when :#{param} is missing" do
        p = @params.tap { |d| d.delete(param) }
        expect { @client.confirm_resource p }.to raise_exception ArgumentError
      end
    end

    it "doesn't confirm the resource when the signature is invalid" do
      @client.expects(:request).never
      @client.confirm_resource({:signature => 'xxx'}.merge(@params)) rescue nil
    end

    it "fails when the signature is invalid" do
      expect do
        @client.confirm_resource({:signature => 'xxx'}.merge(@params))
      end.to raise_exception GoCardless::SignatureError
    end

    it "confirms the resource when the signature is valid" do
      # Once for confirm, once to fetch result
      @client.expects(:request).twice.returns(stub(:parsed => {}))
      @client.confirm_resource(@client.send(:sign_params, @params))
    end

    it "returns the correct object when the signature is valid" do
      @client.stubs(:request).returns(stub(:parsed => {}))
      subscription = GoCardless::Subscription.new_with_client @client
      GoCardless::Subscription.expects(:find_with_client).returns subscription

      # confirm_resource should use the Subcription class because
      # the :response_type is set to subscription
      resource = @client.confirm_resource(@client.send(:sign_params, @params))
      resource.should be_a GoCardless::Subscription
    end

    it "includes valid http basic credentials" do
      GoCardless::Subscription.stubs(:find_with_client)
      auth = 'Basic YWJjOnh5eg=='
      @client.expects(:request).once.with do |type, path, opts|
        opts.should include :headers
        opts[:headers].should include 'Authorization'
        opts[:headers]['Authorization'].should == auth
      end
      @client.confirm_resource(@client.send(:sign_params, @params))
    end

    it "works with string params" do
      @client.stubs(:request)
      GoCardless::Subscription.stubs(:find_with_client)
      params = Hash[@params.dup.map { |k,v| [k.to_s, v] }]
      params.keys.each { |p| p.should be_a String }
      # No ArgumentErrors should be raised
      @client.confirm_resource(@client.send(:sign_params, params))
    end
  end

  it "#generate_nonce should generate a random string" do
    @client.send(:generate_nonce).should_not == @client.send(:generate_nonce)
  end

  describe "#new_limit_url" do
    before(:each) do
      @merchant_id = '123'
      @client.access_token = "TOKEN manage_merchant:#{@merchant_id}"
    end

    def get_params(url)
      Hash[CGI.parse(URI.parse(url).query).map{ |k,v| [k, v.first] }]
    end

    it "should use the correct path" do
      url = @client.send(:new_limit_url, :test_limit, {})
      URI.parse(url).path.should == '/connect/test_limits/new'
    end

    it "should include the params in the URL query" do
      params = { 'a' => '1', 'b' => '2' }
      url = @client.send(:new_limit_url, :subscription, params)
      url_params = get_params(url)
      params.each do |key, value|
        url_params["subscription[#{key}]"].should == value
      end
    end

    it "should add merchant_id to the limit" do
      url = @client.send(:new_limit_url, :subscription, {})
      get_params(url)['subscription[merchant_id]'].should == @merchant_id
    end

    it "should include a valid signature" do
      params = get_params(@client.send(:new_limit_url, :subscription, :x => 1))
      params.key?('signature').should be_true
      sig = params.delete('signature')
      sig.should == @client.send(:sign_params, params.clone)[:signature]
    end

    it "should include a nonce" do
      params = get_params(@client.send(:new_limit_url, :subscription, :x => 1))
      params['nonce'].should be_a String
    end

    it "should include a client_id" do
      params = get_params(@client.send(:new_limit_url, :subscription, :x => 1))
      params['client_id'].should == @client.instance_variable_get(:@app_id)
    end

    it "should include a timestamp" do
      # Time.now returning Pacific time
      time = Time.parse('Sat Jan 01 00:00:00 -0800')
      Time.expects(:now).returns time
      params = get_params(@client.send(:new_limit_url, :subscription, :x => 1))
      # Check that timezone is ISO formatted UTC
      params['timestamp'].should == "2011-01-01T08:00:00Z"
    end
  end

  describe "#merchant_id" do
    it "returns the merchant id when an access token is set" do
      @client.access_token = 'TOKEN manage_merchant:123'
      @client.send(:merchant_id).should == '123'
    end

    it "fails if there's no access token" do
      expect do
        @client.send(:merchant_id)
      end.to raise_exception GoCardless::ClientError
    end
  end
end
