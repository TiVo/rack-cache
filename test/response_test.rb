require_relative 'test_helper'

describe Rack::Cache::Response do
  before do
    @now = Time.httpdate(Time.now.httpdate)
    @one_hour_ago = Time.httpdate((Time.now - (60**2)).httpdate)
    @one_hour_later = Time.httpdate((Time.now + (60**2)).httpdate)
    @res = Rack::Cache::Response.new(200, {'Date' => @now.httpdate}, [])
  end

  after do
    @now, @res, @one_hour_ago = nil
  end

  it 'marks Rack tuples with string typed statuses as cacheable' do
    @res = Rack::Cache::Response.new('200',{'Date' => @now.httpdate},[])
    @res.headers['Expires'] = @one_hour_later.httpdate
    assert @res.cacheable?
  end

  it 'responds to #to_a with a Rack response tuple' do
    assert @res.respond_to? :to_a
    @res.to_a.must_equal [200, {'Date' => @now.httpdate}, []]
  end

  describe '#cache_control' do
    it 'handles multiple name=value pairs' do
      @res.headers['Cache-Control'] = 'max-age=600, max-stale=300, min-fresh=570'
      @res.cache_control['max-age'].must_equal '600'
      @res.cache_control['max-stale'].must_equal '300'
      @res.cache_control['min-fresh'].must_equal '570'
    end
    it 'removes the header when given an empty hash' do
      @res.headers['Cache-Control'] = 'max-age=600, must-revalidate'
      @res.cache_control['max-age'].must_equal '600'
      @res.cache_control = {}
      @res.headers.wont_include 'Cache-Control'
    end
  end

  describe '#validateable?' do
    it 'is true when Last-Modified header present' do
      @res = Rack::Cache::Response.new(200, {'Last-Modified' => @one_hour_ago.httpdate}, [])
      assert @res.validateable?
    end
    it 'is true when ETag header present' do
      @res = Rack::Cache::Response.new(200, {'ETag' => '"12345"'}, [])
      assert @res.validateable?
    end
    it 'is false when no validator is present' do
      @res = Rack::Cache::Response.new(200, {}, [])
      refute @res.validateable?
    end
  end

  describe '#date' do
    it 'uses the Date header if present and parseable' do
      @res = Rack::Cache::Response.new(200, {'Date' => @one_hour_ago.httpdate}, [])
      @res.date.must_equal @one_hour_ago
    end
    it 'returns the current time if present but not parseable' do
      @res = Rack::Cache::Response.new(200, {'Date' => "Jun, 30 Mon 2014 20:10:46 GMT"}, [])
      @res.date.to_i.must_be_close_to Time.now.to_i, 1
    end
    it 'uses the current time when no Date header present' do
      @res = Rack::Cache::Response.new(200, {}, [])
      @res.date.to_i.must_be_close_to Time.now.to_i, 1
    end
    it 'returns the correct date when the header is modified directly' do
      @res = Rack::Cache::Response.new(200, { 'Date' => @one_hour_ago.httpdate }, [])
      @res.date.must_equal @one_hour_ago
      @res.headers['Date'] = @now.httpdate
      @res.date.must_equal @now
    end
  end

  describe '#max_age' do
    it 'uses r-maxage cache control directive when present' do
      @res.headers['Cache-Control'] = 's-maxage=600, max-age=0, r-maxage=100'
      @res.max_age.must_equal 100
    end
    it 'uses s-maxage cache control when no r-maxage directive present' do
      @res.headers['Cache-Control'] = 's-maxage=600, max-age=0'
      @res.max_age.must_equal 600
    end
    it 'falls back to max-age when no r/s-maxage directive present' do
      @res.headers['Cache-Control'] = 'max-age=600'
      @res.max_age.must_equal 600
    end
    it 'falls back to Expires when no max-age or r/s-maxage directive present' do
      @res.headers['Cache-Control'] = 'must-revalidate'
      @res.headers['Expires'] = @one_hour_later.httpdate
      @res.max_age.must_equal 60 ** 2
    end
    it 'gives a #max_age of nil when no freshness information available' do
      @res.max_age.must_be_nil
    end
  end

  describe '#private=' do
    it 'adds the private Cache-Control directive when set true' do
      @res.headers['Cache-Control'] = 'max-age=100'
      @res.private = true
      @res.headers['Cache-Control'].split(', ').sort.
        must_equal ['max-age=100', 'private']
    end
    it 'removes the public Cache-Control directive' do
      @res.headers['Cache-Control'] = 'public, max-age=100'
      @res.private = true
      @res.headers['Cache-Control'].split(', ').sort.
        must_equal ['max-age=100', 'private']
    end
  end

  describe '#expire!' do
    it 'sets the Age to be equal to the max-age' do
      @res.headers['Cache-Control'] = 'max-age=100'
      @res.expire!
      @res.headers['Age'].must_equal '100'
    end
    it 'sets the Age to be equal to the r-maxage when the three max-age and r/s-maxage present' do
      @res.headers['Cache-Control'] = 'max-age=100, s-maxage=500, r-maxage=900'
      @res.expire!
      @res.headers['Age'].must_equal '900'
    end
    it 'sets the Age to be equal to the s-maxage when both max-age and s-maxage present' do
      @res.headers['Cache-Control'] = 'max-age=100, s-maxage=500'
      @res.expire!
      @res.headers['Age'].must_equal '500'
    end
    it 'does nothing when the response is already stale/expired' do
      @res.headers['Cache-Control'] = 'max-age=5, s-maxage=500'
      @res.headers['Age'] = '1000'
      @res.expire!
      @res.headers['Age'].must_equal '1000'
    end
    it 'does nothing when the response does not include freshness information' do
      @res.expire!
      @res.headers.wont_include 'Age'
    end
  end

  describe '#ttl' do
    it 'is nil when no Expires or Cache-Control headers present' do
      @res.ttl.must_be_nil
    end
    it 'uses the Expires header when no max-age is present' do
      @res.headers['Expires'] = (@res.now + (60**2)).httpdate
      @res.ttl.must_be_close_to(60**2, 1)
    end
    it 'returns negative values when Expires is in part' do
      @res.ttl.must_be_nil
      @res.headers['Expires'] = @one_hour_ago.httpdate
      @res.ttl.must_be :<, 0
    end
    it 'uses the Cache-Control max-age value when present' do
      @res.headers['Cache-Control'] = 'max-age=60'
      @res.ttl.must_be_close_to(60, 1)
    end
  end

  describe '#vary' do
    it 'is nil when no Vary header is present' do
      @res.vary.must_be_nil
    end
    it 'returns the literal value of the Vary header' do
      @res.headers['Vary'] = 'Foo Bar Baz'
      @res.vary.must_equal 'Foo Bar Baz'
    end
    it 'can be checked for existence using the #vary? method' do
      assert @res.respond_to? :vary?
      refute @res.vary?
      @res.headers['Vary'] = '*'
      assert @res.vary?
    end
  end

  describe '#vary_header_names' do
    it 'returns an empty Array when no Vary header is present' do
      assert @res.vary_header_names.empty?
    end
    it 'parses a single header name value' do
      @res.headers['Vary'] = 'Accept-Language'
      @res.vary_header_names.must_equal ['Accept-Language']
    end
    it 'parses multiple header name values separated by spaces' do
      @res.headers['Vary'] = 'Accept-Language User-Agent    X-Foo'
      @res.vary_header_names.must_equal \
        ['Accept-Language', 'User-Agent', 'X-Foo']
    end

    it 'parses multiple header name values separated by commas' do
      @res.headers['Vary'] = 'Accept-Language,User-Agent,    X-Foo'
      @res.vary_header_names.must_equal \
        ['Accept-Language', 'User-Agent', 'X-Foo']
    end
  end

  describe '#expires' do
    it 'returns nil if there is no Expires header' do
      @res.headers['Expires'] = nil
      @res.expires.must_be_nil
    end

    it 'returns a Time if the Expires header is parseable' do
      @res.headers['Expires'] = "Mon, 30 Jun 2014 20:10:46 GMT"
      @res.expires.must_equal Time.at(1404159046)
    end

    it 'returns nil if the Expires header is not parseable' do
      @res.headers['Expires'] = "Jun, 30 Mon 2014 20:10:46 GMT"
      @res.expires.must_be_nil
    end
  end
end
