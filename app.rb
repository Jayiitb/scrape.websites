require "sinatra"
require "nokogiri"
require 'mechanize'
require 'open-uri'
require "net/http"
require "uri"
require "pry"
require 'sinatra/base'

# Doc Structure
# LAT  LNG  TITLE  FETCHED_CITY  EXACT_ADDRESS PHONE1  PHONE2  VERIFIED  ESTDIN  RATING

CATEGORY_SUGGEST_API_URL = "http://www.justdial.com/autosuggest.php?cases=what&search="
# http://www.justdial.com/Bangalore/SAP-Training-Institutes
get '/' do
	"Go to /scrape/jd/CityName/CategoryName"
end

get "/scrape/jd/:city/:category" do
	city = params['city'].capitalize
	category = params['category']
	subcats = category.split("+")
	category_file_name, category_fetching_name, category_match_name = "", "", ""
	subcats.each_with_index do |subcat,index|
		if(index==0)
			category_file_name += "#{subcat}"
			category_match_name += "#{subcat.capitalize}"
			category_fetching_name += "#{subcat.capitalize}"
		else
			category_file_name += "_#{subcat}"
			category_match_name += "#{subcat.capitalize}"
			category_fetching_name += "-#{subcat.capitalize}"
		end
	end

	uri = URI.parse("#{CATEGORY_SUGGEST_API_URL}#{category}")
	http = Net::HTTP.new(uri.host, uri.port)
	request = Net::HTTP::Get.new(uri.request_uri)
	response = http.request(request)
	if response and response.body 
		parsed_body = JSON.parse response.body
		if parsed_body["results"] and parsed_body["results"][0] and  parsed_body["results"][0]["oval"] and (parsed_body["results"][0]["oval"].gsub(/[\s\t\n]/,'') == category_match_name)
			# Category = "Book Shops" compared with "BookShops" after trimming white spaces
			category_id = parsed_body["results"][0]["id"] 
		end
	end
	if category_id
		fetching_url = "http://www.justdial.com/#{city}/#{category}/ct-#{category_id}/page-1"
		agent = Mechanize.new
		html = agent.get(fetching_url).body
		html_doc = Nokogiri::HTML(html)
		rows = "Lat, Lng, Title, Area, Phone1, Phone2, Verified, EstdIn, Rating\n"

		rows = "LAT, LNG, TITLE, CITY, EXACT_ADDRESS, PHONE1, PHONE2, VERIFIED, ESTABLISHED IN, RATING\n"

		fp = File.new("#{params['city']}_#{category_file_name}.csv", "w")

		if html_doc.css("#srchpagination a:nth-last-child(2)") and html_doc.css("#srchpagination a:nth-last-child(2)").text
			pages = html_doc.css("#srchpagination a:nth-last-child(2)").text.to_i
		end
		
		i = 1
		while (pages > 0) and (i <= pages)
			rows += "\n"

			if i > 1
				fetching_url = "http://www.justdial.com/#{city}/#{category_fetching_name}/ct-#{category_id}/page-#{i}"
				html = agent.get(fetching_url).body
				html_doc = Nokogiri::HTML(html)
			end

			if (i == pages)
				# Increase Page if More Pages are Available
				if html_doc.css("#srchpagination a:nth-last-child(2)") and html_doc.css("#srchpagination a:nth-last-child(2)").text
					pages = html_doc.css("#srchpagination a:nth-last-child(2)").text.to_i
				end
			end

			puts "Crawling Page #{i}"

			# Doing Stuffs for a Particular Page
			main_els = html_doc.css(".jgbg, .jbbg")
			main_els.each do |el|
				lat_lng, title, fetched_city, exact_address, phone1, phone2, verified, estdIn, rating = "'', '', ", "", "", "", "", "", false, "", ""
				if  el.css(".rsmap") and el.css(".rsmap").length > 0
					puts el.css(".rsmap").length
					lat_lng = el.css(".rsmap")[0]["onclick"]
					lat_lng = lat_lng.gsub(/view_map.*#{city}', /,'').gsub(/ 'bcard.*/,'').gsub(/'/,'')
					
				end

				title = el.css(".jcn a").first["title"] if el.css(".jcn a") and el.css(".jcn a").first
				title,fetched_city = title.split(" in ") if title
				fetched_city = fetched_city.gsub(/,/,'-') if fetched_city
				exact_address = el.css(".mrehover.dn")[0].text.gsub(/[\t\n]/,'').gsub(/,/,'-') if el.css(".mrehover.dn") and el.css(".mrehover.dn")[0] and el.css(".mrehover.dn")[0].text
					# Lat, Lng, Title, fetched_city, exact_address

				phones = el.css(".compdt .jrcw a")#.first["href"]
				if phones and phones.count
					phones.each_with_index do |phone,index|
						number = phone["href"]
						number = number.gsub(/tel:/,'')
						(index == 0) ? phone1 = number : phone2 = number
					end
				end

				estdIn = el.css(".estd span:nth-child(2)").text.gsub!(/[^0-9A-Za-z]/, '') if el.css(".estd span:nth-child(2)") and el.css(".estd span:nth-child(2)").text
				rating = el.css(".fctrtng .fctrnam").text.gsub!(/[^0-9A-Za-z]/, '') if el.css(".fctrtng .fctrnam") and el.css(".fctrtng .fctrnam").text
				rating = rating.gsub(/Ratings/,'') if rating
				verified = el.css(".trjdvrfy a").first["class"] == "jdvn"

				rows += "#{lat_lng} #{title}, #{fetched_city}, #{exact_address}, #{phone1}, #{phone2}, #{verified}, #{estdIn}, #{rating} \n"
				# LAT  LNG  TITLE  FETCHED_CITY  EXACT_ADDRESS PHONE1  PHONE2  VERIFIED  ESTDIN  RATING
			end

			i += 1
		end

		fp.puts("#{rows}\n\n")
		fp.close
	else
		puts "No Matching City or Category...Please check"
	end
end


