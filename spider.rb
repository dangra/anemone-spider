#!/usr/bin/env ruby
require 'rubygems'
require 'bundler/setup'
require 'json'
require 'net/http'
require 'uri'
require 'anemone'


JOBDATA = JSON.parse(File.read(ENV['JOB_DATA']))
HUBSTORAGE = ENV.fetch('SHUB_STORAGE', 'https://storage.scrapinghub.com')


class Uploader

  attr_accessor :jobkey
  attr_accessor :prefix
  attr_accessor :endpoint
  attr_accessor :offset
  attr_accessor :batch
  attr_accessor :batchsize
  attr_accessor :count

  def initialize(key, auth, prefix='items', endpoint=HUBSTORAGE)
    @key = key
    @auth = auth
    @prefix = prefix
    @endpoint = endpoint
    @offset = 0
    @batch = []
    @batchsize = 3
    @count = 0
  end

  def add(item)
    @count += 1
    @batch << item
    if @batch.length % @batchsize == 0
      commit()
    end
  end

  def commit()
    return if @batch.empty?
    upload(@prefix, @batch, {:start => @offset})
    @offset += @batch.length
    @batch = []
  end

  private
  def upload(prefix, items, params)
    uri = URI("#{@endpoint}/#{@prefix}/#{@key}")
    uri.query = URI.encode_www_form(params)
    http = Net::HTTP.new(uri.host, uri.port)
    req = Net::HTTP::Post.new(uri.request_uri)
    req.basic_auth(@auth[0], @auth[1])
    req.body = items.map(&:to_json).join('\n')
    req.content_type = 'application/x-jsonlines'
    puts "#{req.method} #{req.path} #{items.length} #{req.body.length}"
    res = http.request(req)
    puts "#{res.code} #{res.body()}"
  end
end


jobkey = JOBDATA['key']
auth = [JOBDATA['key'], JOBDATA['auth']]
auth = ['vagrant', ENV['HSAPIKEY']]
puts auth
itemup = Uploader.new(jobkey, auth, 'items')
logup = Uploader.new(jobkey, auth, 'logs')

TITLE = "//div[@class='pmovie']/h1"
DESC = "//div[@class='pmovie']/div[@class='details']"
IMAGE = "//div[@class='pmovie']/img[@class='poster']"
Anemone.crawl("http://www.argenteam.net/") do |anemone|
  anemone.on_pages_like(/movie\/\d+\/.*/) do |page|
    title = page.doc.at_xpath(TITLE).text rescue nil
    description = page.doc.at_xpath(DESC).text rescue nil
    image = page.doc.at_xpath(IMAGE).attribute("src") rescue nil
    item = {:url => page.url,
            :title => title,
            :description => description,
            :images => [image]}
    itemup.add(item)
    logup.add({:message => "Crawled #{page.url}"})

    # Give up after 7 items
    if itemup.count > 7
      itemup.commit()
      exit
    end
  end
end
