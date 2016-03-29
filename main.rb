require 'httparty'
require 'pry'
require 'nokogiri'
require 'json'
require 'uri'
require 'chronic'

module Attributes
  module_function
  def attrs; [:fashionshowname, :year, :month, :city, :brandname, :order, :modelname, :modelagency]; end
  
  def self.included(base)
    puts 'extended'
  end
end

class DataEntry
  include Attributes
  
  Attributes::attrs.each do |attr|
    attr_accessor attr
  end
  
  define_method :to_string do
    first_col = true
    str = ''
    Attributes::attrs.each do |attr|
      if not first_col
        str = "#{str}, "
      else
        first_col = false
      end
      a = eval(attr.to_s)
      str = "#{str}#{a}"
    end
    str
  end
end

module Main
  include Attributes
  
  result = []
  
  # address = 'http://www.vogue.com/fashion-shows/spring-2015-couture/alexandre-vauthier'
  address = 'http://www.vogue.com/fashion-shows/spring-2015-couture/alexis-mabille'
  page = HTTParty.get(address)
  parse_page = Nokogiri::HTML(page)
  script = parse_page.css('#initial-state').text
  decoded_script = URI.unescape(script)
  parse_script = JSON.parse(decoded_script)
  
  data = parse_script["context"]["dispatcher"]["stores"]["RunwayLandingStore"]["data"]
  
  f = File.new('raw.rb', 'w')
  f.write(parse_script)
  f.close
  Pry.start(binding)
  
  fashionshowname = data['season']['name']
  year = Chronic::parse(data['eventDate']).year
  month = Chronic::parse(data['eventDate']).month
  city = data['city']['name']
  brandname = data['brand']['name']
  
  order = 0
  data['slideShows']['collection']['slides'].each do |slide|
    models = slide['taggedPeople']
    order += 1
    
    if models.empty?
      modelname_and_agency = slide['slideDetails']['caption']
      modelname = modelname_and_agency.split(' (')[0]
      modelagency = modelname_and_agency[/\(.*?\)/]
      next
    end
    
    index = 0
    models.each do |model|
      # index += 1
      # next if index < order
      puts "#{order} #{index}"
      next if index != order - 1
      break if model['agencies'].nil?
      
      modelname = model['name']
      modelagency = ''

      agencies = model['agencies']
      agencies.each do |agency|
        next unless agency['city']['name'].eql? city
        modelagency = agency['name']
        break
      end
      
      entry = DataEntry.new
      Attributes::attrs.each do |attr|
        next if not local_variables.include? attr
        entry.send("#{attr}=".to_sym, eval(attr.to_s))
      end
      result.push(entry)
    end
  end
  
  f = File.new('data.csv', 'w')
  result.each do |entry|
    puts entry.to_string
    f.write(entry.to_string)
    f.write("\n")
  end
  f.close
end