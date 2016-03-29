require 'httparty'
require 'pry'
require 'nokogiri'
require 'json'
require 'uri'
require 'chronic'

module Constants
  module_function
  def attrs; [:fashionshowname, :year, :month, :city, :brandname, :order, :modelname, :modelagency]; end
  def base_url; 'http://www.vogue.com/fashion-shows'; end
  def flag=(flag); @flag=flag; end
  def flag; @flag; end
  def last_address=(last_address); @last_address=last_address; end
  def last_address; @last_address; end
  
  def self.included(base)
    puts 'extended'
  end
end

class DataEntry
  include Constants
  
  Constants::attrs.each do |attr|
    attr_accessor attr
  end
  
  define_method :to_string do
    first_col = true
    str = ''
    Constants::attrs.each do |attr|
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

module ScrapModels
  module_function
  include Constants
  
  def run(address)
    puts "#{address}"
    return [] if (Constants::flag and (not Constants::last_address.eql? address))
    Constants::flag = false

    result = []
    
    page = HTTParty.get(address)
    parse_page = Nokogiri::HTML(page)
    script = parse_page.css('#initial-state').text
    decoded_script = URI.unescape(script)
    parse_script = JSON.parse(decoded_script)
    
    data = parse_script["context"]["dispatcher"]["stores"]["RunwayLandingStore"]["data"]
    # Pry.start(binding)
    
    return [] if data['slideShows'].nil? || data['slideShows'].empty?
    
    fashionshowname = data['season']['name']
    parsed_time = Chronic::parse(data['eventDate'])
    year = parsed_time.year if not parsed_time.nil?
    month = parsed_time.month if not parsed_time.nil?
    city = data['city']['name']
    brandname = data['brand']['name']
    
    order = 0
    data['slideShows']['collection']['slides'].each do |slide|
      models = slide['taggedPeople']
      order += 1
      
      if models.empty?
        modelname_and_agency = slide['slideDetails']['caption']
        if modelname_and_agency.nil? or modelname_and_agency.empty?
          # nil guard
        else
          modelname = modelname_and_agency.split(' (')[0]
          if modelname_and_agency.include? '('
            modelagency = modelname_and_agency.match(/(\((.*)\))/)[2]
          end
        end
      else
        models.each do |model|
          break if model['agencies'].nil?
          
          modelname = model['name']
          modelagency = ''
    
          agencies = model['agencies']
          agencies.each do |agency|
            next unless agency['city']['name'].eql? city
            modelagency = agency['name']
            break
          end
        end
      end
      
      next if modelname.nil? || modelname.empty?
      
      entry = DataEntry.new
      Constants::attrs.each do |attr|
        next if not local_variables.include? attr
        entry.send("#{attr}=".to_sym, eval(attr.to_s))
      end
      result.push(entry)
    end
    
    result
  end
end

module ScrapSeasons
  module_function
  include Constants

  def run(address)
    page = HTTParty.get(address)
    parse_page = Nokogiri::HTML(page)
    script = parse_page.css('#initial-state').text
    decoded_script = URI.unescape(script)
    parse_script = JSON.parse(decoded_script)
    
    seasons = parse_script['context']['dispatcher']['stores']['RunwayLandingStore']['data']['content']
    seasons_url = []
    seasons.each do |season|
      seasons_url.push(season['urlFragment'])
    end
    
    seasons_url
  end
end

module ScrapShows
  module_function
  include Constants
  
  def run(address)
    page = HTTParty.get(address)
    parse_page = Nokogiri::HTML(page)
    script = parse_page.css('#initial-state').text
    decoded_script = URI.unescape(script)
    parse_script = JSON.parse(decoded_script)
    
    shows = parse_script['context']['dispatcher']['stores']['RunwayLandingStore']['data']['fashionShows']
    shows_url = []
    shows.each do |show|
      shows_url.push(show['brandUrlFragment'])
    end
    
    shows_url
  end
end

module Main
  include Constants
  include ScrapSeasons
  include ScrapShows
  include ScrapModels
  
  Constants::flag = true
  Constants::last_address = 'http://www.vogue.com/fashion-shows/resort-2015/mulberry'
  
  seasons_url = ScrapSeasons.run("#{Constants::base_url}")
  seasons_url.each do |season_url|
    shows_url = ScrapShows::run("#{Constants::base_url}/#{season_url}")
    shows_url.each do |show_url|
      filename = "./data/#{season_url}_#{show_url}.csv"
      next if File.exist? filename
      
      result = ScrapModels::run("#{Constants::base_url}/#{season_url}/#{show_url}")
      # result = ScrapModels::run('http://www.vogue.com/fashion-shows/pre-fall-2015/gucci')

      next if result.empty?
      
      f = File.new(filename, 'w')
      f.write("fashionshowname,year,month,city,brandname,order,modelname,modelagency\n")
      result.each do |entry|
        puts entry.to_string
        f.write(entry.to_string)
        f.write("\n")
      end
      f.close
      
      sleep(rand(5..10))
    end
  end
  
  # Pry.start(binding)
end