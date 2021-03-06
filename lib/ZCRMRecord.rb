require 'ZohoCRM_Client'

class ZCRMRecord

	def initialize(module_name, hash_values, fields, mod_obj=nil)
		@module_name = module_name
		@hash_values = hash_values
		@fields = fields
		@modified_fields = {}
		@added_fields = {}
		@unavailable_fields = []
		@fields_sent_lastupdate = []
		@error_fields_lastupdate = []
		@is_deleted = false
		@is_record_marked_for_deletion = false
		if !hash_values.nil? then
			@record_id = hash_values['id']
		else
			@record_id = nil
		end
		@required_fields = []
		@module_obj = mod_obj
		@layout = nil
		if !mod_obj.nil? then
			@layout = mod_obj.default_layout
		end
		@is_related_list = false
		@related_list_obj = nil
		@owner_id = nil
	end

	def set_related_list_obj(rel_obj)
		if !rel_obj.nil? && rel_obj.class == RelatedList then
			@is_related_list = true
			@related_list_obj = rel_obj
		end
	end

	def set_record_id(id)
		@record_id = id
	end

	def layout_id
		return @layout.id
	end

	def self.get_file_name(file_path)
		if file_path.nil? || file_path.empty? then
			return file_path
		end
		if file_path.include? "/" then
			return file_path
		end
		temp_arr = file_path.split("/")
		return temp_arr[temp_arr.length - 1]
	end

	def set_layout(layout)
		if layout.class == ZCRMLayout then
			@layout = layout
		end
	end

	def set_layout_id(layout_id)
		if @module_obj.nil? then
			return false
		end
		l = @module_obj.get_layout(layout_id)
		if !l.nil? then
			@layout = l
		end
	end

	def get_hash_values
		return @hash_values
	end

	def check_module_obj
		if @module_obj.nil? then
			return false
		else
			return true
		end
	end
	
	def get_attachments
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Please set module object before proceeding ::: ")
			return false, {}
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is not set ::: ")
			return false,{}
		end
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Attachments"

		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Attachments"
		headers = zclient.construct_headers
		params = {}
		response = zclient.safe_get(url, params, headers)
		if response.nil? then
			throw BadRequestException.new
		end
		code = response.code.to_i
		if code == 204 then
			return true, {}
		end
		ZohoCRMClient.debug_log("Returned response for get attachments ===> #{response}")
		body = response.body
		ZohoCRMClient.debug_log("Body ===> #{body}")
		list = Api_Methods._get_list(body, "data")
		result_data = {}
		list.each do |json|
			id = json['id']
			result_data[id] = json
		end
		return true, result_data
	end

	def upload_attachment(file_path, file_type="image/pdf")
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Please set module_obj and proceed ::: ")
			return false, nil
		end

		if @record_id.nil? then
			ZohoCRMClient.debug_log("The record id is not set ::: ")
			return false, nil
		end

		if file_path.nil? || file_path.empty? then
			return false, nil
		end

		if file_type.nil? || file_type.empty? then
			return false, nil
		end

		#url_str = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Attachments"
		zclient = @module_obj.get_zclient
		url_str = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Attachments"
		ZohoCRMClient.debug_log("the url ==> #{url_str}")
		headers = zclient.construct_headers
		params = {}

		file = nil
		file_name = nil
		begin
			file = File.open(file_path)
		rescue => e
			ZohoCRMClient.debug_log("Error while opening file ==> #{file_path}")
			ZohoCRMClient.debug_log("Printing exception ==> #{e}")
			return false, nil
		end
		temp_arr = file_path.split("/")
		file_name = temp_arr[temp_arr.length-1]

		url = URI.parse(url_str)
		http = Net::HTTP.new(url.host, url.port)
		http.use_ssl = (url.scheme == "https")
		req = Net::HTTP::Post::Multipart.new url.path, "file" => UploadIO.new(file, file_type, file_name)
		headers.each do |key, value|
			ZohoCRMClient.debug_log("Header Key value ===> #{key}, #{value}")
			req.add_field(key, value)
		end
		res = http.request(req)
		code = res.code.to_i
		body = res.body
		ZohoCRMClient.debug_log("code ===> #{code}")
		ZohoCRMClient.debug_log("body ===> #{body}")

		body = nil
		if code == 401 then
			if zclient.revoke_token then
				headers = zclient.construct_headers
				headers.each do |key, value|
					req.add_field(key, value)
				end
				res = http.request(req)
			else
				raise InvalidTokensError.new()
			end
		elsif code == 400 then
			raise BadRequestException.new()
		end
		code = res.code.to_i
		if code == 200 then
			body = res.body
		elsif code == 401 then
			raise InvalidTokensError.new()
		end

		list = Api_Methods._get_list(body, "data")
		if list.length > 0 then
			json = list[0]
			if json.has_key?("code") then
				code = json["code"]
				details = json["details"]
				id = details["id"]
				if code.downcase == "success" then	
					return true, id
				else
					return false, id
				end
			else
				return false, nil
			end
		else
			return false, nil
		end
	end

	def download_attachment(attachment_id, file_name="default_file_name")
		orig_name = file_name
		#todo typing here
		if attachment_id.nil? || attachment_id.to_s.empty? then
			return false, nil
		end
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Module object is not set. Please check and proceed ")
			return false, nil
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is nil. Please check and proceed")
			return false, nil
		end
		#url_str = Constants::DEF_CRMAPI_URL + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + self.record_id + 
		#Constants::URL_PATH_SEPERATOR + "Attachments" + Constants::URL_PATH_SEPERATOR + attachment_id
		
		zclient = @module_obj.get_zclient
		url_str = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + self.record_id + 
		Constants::URL_PATH_SEPERATOR + "Attachments" + Constants::URL_PATH_SEPERATOR + attachment_id
		ZohoCRMClient.debug_log("URL ==> #{url_str}")
		headers = zclient.construct_headers
		response = zclient.safe_get(url_str, {}, headers)
		if !response.nil? && response.class == RestClient::Response then
			code = response.code.to_i
			if code == 200 then
				body = response.body
				counter = 1
				while File.exists?(file_name) do
					file_name = orig_name + "(" + counter.to_s + ")"
					counter = counter + 1
				end
				file = File.open(file_name, "w")
				file.write(body)
				return true, file_name
			else
				return false, nil
			end
		else
			return false, nil
		end
	end

	def upload_photo(image_path, type="image/jpeg")
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Module object is not set. Please set it and proceed.")
			return false
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is nil. Please set it and proceed.")
			return false
		end
		if image_path.nil? || image_path.empty? then
			return false
		end
		if !File.exists?(image_path) then
			return false
		end
		if type.nil? || type.empty? then
			return false
		end
		if @module_name != "Leads" && @module_name != "Contacts" then
			return false
		end

		#url_str = Constants::DEF_CRMAPI_URL + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "photo"
		zclient = @module_obj.get_zclient
		url_str = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "photo"
		url = URI.parse(url_str)
		begin
			img_file = File.open(image_path)
		rescue => e
			ZohoCRMClient.debug_log("Exception while opening given file ==> #{img_file} ")
			ZohoCRMClient.debug_log("Priting exception ==> #{e}")
			return false
		end
		file_name = ZCRMRecord.get_file_name(image_path)
		
		headers = zclient.construct_headers

		http = Net::HTTP.new(url.host, url.port)
		http.use_ssl = (url.scheme == "https")
		req = Net::HTTP::Post::Multipart.new url.path, "file" => UploadIO.new(img_file, type, file_name)
		headers.each do |key, value|
			req.add_field(key, value)
		end
		res = http.request(req)
		code = res.code.to_i
		body = nil
		if code == 401 then
			if zclient.revoke_token then
				headers = zclient.construct_headers
				headers.each do |key, value|
					req.add_field(key, value)
				end
				res = http.request(req)
			else
				raise InvalidTokensError.new()
			end
		elsif code == 400 then
			raise BadRequestException.new()
		end
		code = res.code.to_i
		if code == 200 then
			body = res.body
		elsif code == 401 then
			raise InvalidTokensError.new()
		end
		body = res.body
		ZohoCRMClient.debug_log("body content for upload_photo : #{body}")
		body_hash = JSON.parse(body)
		if body_hash.has_key?("code") then
			message = body_hash["code"]
			if message.downcase == "success" then
				return true
			else
				return false
			end
		else
			return false
		end
	end

	def download_photo(file_name = "default_image_name")
		orig_name = file_name
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Module object is not set. Please check and proceed.")
			return false
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is nil. Please check and proceed.")
			return false
		end
		module_name = @module_obj.module_name
		if module_name != "Leads" && module_name != "Contacts" then
			ZohoCRMClient.debug_log("Download and upload photo is supported only for Leads and Contact modules")
			return false
		end
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "photo"

		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "photo"
		headers = zclient.construct_headers
		response = zclient.safe_get(url, {}, headers)
		if response.nil? then
			return false
		end
		code = response.code.to_i
		file = nil
		body = nil
		if code == 200 then
			body = response.body
			counter = 1
			while File.exists?(file_name) do
				file_name = orig_name + "(" + counter.to_s + ")"
				counter = counter + 1
			end
			file = File.open(file_name, "w")
			file.write(body)
			file.close
			return true, file_name
		elsif code == 204 then
			ZohoCRMClient.debug_log("204 No Content")
			return true, ""
		else
			ZohoCRMClient.debug_log("Response status is ==> #{code}")
			return false
		end

	end

	def get_notes
		if @module_obj.nil? then
			ZohoCRMClient.debug_log "Please set the module_obj for the record and proceed."
			return false, {}
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is nil. Please check and proceed.")
			return false, {}
		end
		return_hash = {}
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Notes"
		
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + "Notes"
		ZohoCRMClient.debug_log("URL ==> #{url}")
		headers = zclient.construct_headers
		params = {}
		response = zclient.safe_get(url, params, headers)
		if response.nil? then
			return false, {}
		end
		code = response.code.to_i
		ZohoCRMClient.debug_log("Status code ===> #{code}")
		if code == 200 then
			body = response.body
			notes_list = Api_Methods._get_list(body, "data")
			notes_list.each do |json|
				#note_obj = ZCRMRecord.new(notes_mod_obj.api_name, json, notes_mod_obj.get_fields, notes_mod_obj)
				note_obj = ZCRMNote.new(json)
				note_id = note_obj.id
				return_hash[note_id] = note_obj
			end
			return true, return_hash
		elsif code == 204 then
			return true, {}
		else
			ZohoCRMClient.debug_log("Improper status code ==> #{code}")
			return false, {}
		end
				
	end

	def create_note(note_title="", note_content="")
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Please set module_obj for the record and proceed ::: ")
			return false
		end

		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record id is nil. Please check and proceed.")
			return false
		end

		if note_content.nil? || note_content.empty? then
			return false
		end
		

		note_json = {}
		if note_title.nil? then
			note_json['Note_Title'] = note_title
		end
		note_json['Note_Content'] = note_content

		arr = []
		arr[0] = note_json
		final_hash = {}
		final_hash['data'] = arr
		json = JSON::generate(final_hash)
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + 'Notes' 
		
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + self.record_id + Constants::URL_PATH_SEPERATOR + 'Notes' 
		ZohoCRMClient.debug_log("The URL ==> #{url}")
		headers = zclient.construct_headers
		params = {}
		ZohoCRMClient.debug_log("JSON for create note ==> #{json}")
		begin
			response = zclient.safe_upsert_post(url, params, headers, json)
		rescue => e
			return false, nil
		end
		zclient.update_limits_HTTPRESPONSE(response)
		code = response.code.to_i
		if code > 204 then
			ZohoCRMClient.debug_log("Invalid status code while creating note ==> #{code}")
			return false, nil
		end
		body = response.body
		notes = Api_Methods._get_list(body, "data")
		success_ids = []
		failure_ids = []
		notes.each do |note_json|
			message = note_json["code"]
			temp_id = nil
			if note_json.has_key?("details") then
				details = note_json["details"]
				temp_id = details["id"]
			end
			if message.downcase == "success" then
				success_ids[success_ids.length] = temp_id
			else
				failure_ids[failure_ids.length] = temp_id
			end
		end
		if failure_ids.length > 0 then
			return false, failure_ids[0]
		elsif success_ids.length > 0 then
			return true, success_ids[0]
		else
			return false, nil
		end

	end

	def update_notes(notes={})
		if @module_obj.nil? then
			ZohoCRMClient.debug_log("Module object is not set. Please check and proceed. ")
			return false
		end
		if @record_id.nil? then
			ZohoCRMClient.debug_log("Record object does not have record_id. Please check and proceed. ")
			return false
		end
		if notes.nil? || notes.empty? then
			ZohoCRMClient.debug_log("There aren't any notes to update. Please check.")
			return false
		end
		sent_ids = []
		final_json = ""
		arr = []
		final_hash = {}
		notes.each do |id, note|
			note_hash = note.construct_update_hash
			arr[arr.length] = note_hash
			sent_ids[sent_ids.length] = id
		end
		final_hash["data"] = arr
		final_json = JSON.generate(final_hash)
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + "Notes"
		
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + "Notes"
		ZohoCRMClient.debug_log("URL ==> #{url}")
		headers = zclient.construct_headers
		ZohoCRMClient.debug_log("Final json ==> #{final_json}")
		response = zclient.safe_update_put(url, headers, final_json)
		if response.nil? then
			return false
		end
		zclient.update_limits_HTTPRESPONSE(response)
		code = response.code.to_i
		if code > 204 then
			ZohoCRMClient.debug_log("update_put returned with improper code ==> #{code}")
			return false, "Improper status code"
		end
		body = response.body
		list = Api_Methods._get_list(body, "data")
		success_ids = []
		list.each do |note_json|
			message = note_json["code"]
			if message.downcase == "success" then
				details = note_json["details"]
				id = details["id"]
				success_ids[success_ids.length] = id
			else
				ZohoCRMClient.debug_log("Error record while updating notes ==> #{message}")
			end
		end
		failure_ids = sent_ids - success_ids
		return true, success_ids, failure_ids

	end

=begin
	def update_note(note_title="", note_content="")
		if @module_obj.nil? then
			print "Please set module_obj for the record and proceed ::: "
			return false
		end
		note_json = {}
		note_json['Note_Title'] = note_title
		note_json['Note_Content'] = note_content
		arr = []
		arr[0] = note_json
		final_hash = {}
		final_hash['data'] = arr
		json = JSON::generate(final_hash)
		url = Constants::DEF_CRMAPI_URL + @module_name + URL_PATH_SEPERATOR + self.record_id + URL_PATH_SEPERATOR + "Notes"
		zclient = @module_obj.get_zclient
		headers = zclient.construct_headers
		params = {}
		response = zclient._update_put(url, headers, payload)
		body = response.body
		notes = Api_Methods._get_list(body,"data")
		failed_ids = []
		success_ids = []
		notes.each do |note|
			code = note['code']
			details = note['details']
			id = details['id']
			if code == "SUCCESS" then
				success_ids[success_ids.length] = id
			else
				failed_ids[failed_ids.length] = id
			end
		end
		if failed_ids.length > 0 then
			return false, failed_ids
		else
			return true, []
		end
	end

=end

	def get_related_records(rel_api_name)
		if @module_obj.nil? then
			ZohoCRMClient.debug_log "Please set ZCRMModule object for this ZCRMRecord object and then try. Thanks!"
			return false, {}
		end
		if @record_id.nil? || @record_id.empty? then
			ZohoCRMClient.debug_log("Record id is empty ")
			return false, {}
		end
		rel_obj = @module_obj.get_related_list_obj(rel_api_name)
		if rel_obj.nil? then
			return false, {}
		end
		return_hash = {}
		rel_module_name = rel_obj.module
		rel_api_name = rel_obj.api_name
		is_rel_module = rel_obj.is_module

		mod_api_obj = nil
		if is_rel_module && !rel_module_name.nil? then
			ZohoCRMClient.debug_log("Getting module object => #{rel_module_name}")
			mod_api_obj = @module_obj.load_crm_module(rel_module_name)
		else
			return false, {}
		end

		#url = Constants::DEF_CRMAPI_URL + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + rel_obj.api_name
		
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_obj.module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + rel_obj.api_name
		ZohoCRMClient.debug_log("URL ==> #{url}")
		headers = zclient.construct_headers
		params = {}
		response = zclient.safe_get(url, params, headers)
		code = response.code.to_i
		ZohoCRMClient.debug_log("Code ==> #{code}")
		if code == 204 then
			return true, {}
		end
		body = response.body
		ZohoCRMClient.debug_log("Body ==> #{body}")
		records_json = Api_Methods._get_list(body, "data")
		records_json.each do |record|
			record_obj = nil
			if is_rel_module then
				record_obj = ZCRMRecord.new(rel_module_name, record, mod_api_obj.get_fields, mod_api_obj)
				record_obj.set_related_list_obj(rel_obj)
				id = record_obj.record_id
			else
				record_obj = ZCRMRecord.new(rel_api_name, record, nil, nil)
				record_obj.set_related_list_obj(rel_obj)
				id = record_obj.record_id
			end
			return_hash[id] = record_obj
		end
		return true, return_hash
	end

	def update_related_record(rel_api_name, related_record_id)
		#Returns : boolean,Array of failed ids [Array]
		#https://www.zohoapis.com/crm/v2/Leads/{record_id}/Campaigns/{related_record_id}
		if @module_obj.nil? then
			ZohoCRMClient.log("Please set module_obj and proceed ::: ")
			return false, []
		end
		if @record_id.nil? || @record_id.empty? then
			ZohoCRMClient.log("Record id is not set. Please check and proceed ::: ")
		end

		related_record_obj = @module_obj.get_related_list_obj(rel_api_name)
		if related_record_obj.nil? then
			ZohoCRMClient.debug_log("The given related list module name is not a valid one. Please check.")
			return false, []
		end

		related_module = related_record_obj.module_name

		if !(related_module == "Campaigns" || related_module == "Products") then
			ZohoCRMClient.debug_log "Please check the related module and continue again ::: "
			return false,[]
		else
			ZohoCRMClient.debug_log "Related list module is ==> #{related_module}"
		end

		#related_record_id = related_record_obj.record_id
		record_id = self.record_id
		#url = Constants::DEF_CRMAPI_URL + @module_name + URL_PATH_SEPERATOR + self.record_id + URL_PATH_SEPERATOR + related_module + URL_PATH_SEPERATOR + related_record_id
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + URL_PATH_SEPERATOR + self.record_id + URL_PATH_SEPERATOR + related_module + URL_PATH_SEPERATOR + related_record_id
		headers = zclient.construct_headers
		params = {}
		json = related_record_obj.construct_update_hash
		json_arr = []
		json_arr[0] = json
		final_hash = {}
		final_hash['data'] = json_arr
		final_json = JSON::generate(final_hash)
		response = zclient._put(url, {}, headers, final_json)
		body = response.body
		json_list = Api_Methods._get_list(body, "data")
		success_ids = []
		failure_ids = []
		json_list.each do |json|
			code = json['code']
			details = json['details']
			id = details['id']
			if code == "SUCCESS" then
				success_ids[success_ids.length] = id
			else
				failure_ids[failure_ids.length] = id
			end
		end
		if failure_ids.length > 0 then
			print "There are #{failure_ids.length} failures :::: "
			return false, failure_ids
		else
			return true, failure_ids
		end
	end

	def update_related_record1(related_record_obj)
		#Returns : boolean,Array of failed ids [Array]
		#https://www.zohoapis.com/crm/v2/Leads/{record_id}/Campaigns/{related_record_id}
		if @module_obj.nil? then
			ZohoCRMClient.log("Please set module_obj and proceed ::: ")
			return false, []
		end
		if @record_id.nil? || @record_id.empty? then
			ZohoCRMClient.log("Record id is not set. Please check and proceed ::: ")
		end

		related_module = related_record_obj.module_name

		if not (related_module == "Campaigns" || related_module == "Products")
			print "Please check the related module and continue again ::: "
		else
			print "The related list module is all fine, you can continue ::: "
		end

		related_record_id = related_record_obj.record_id
		record_id = self.record_id
		#url = Constants::DEF_CRMAPI_URL + @module_name + URL_PATH_SEPERATOR + self.record_id + URL_PATH_SEPERATOR + related_module + URL_PATH_SEPERATOR + related_record_id
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + URL_PATH_SEPERATOR + self.record_id + URL_PATH_SEPERATOR + related_module + URL_PATH_SEPERATOR + related_record_id
		headers = zclient.construct_headers
		params = {}
		json = related_record_obj.construct_update_hash
		json_arr = []
		json_arr[0] = json
		final_hash = {}
		final_hash['data'] = json_arr
		final_json = JSON::generate(final_hash)
		response = zclient._put(url, {}, headers, final_json)
		body = response.body
		json_list = Api_Methods._get_list(body, "data")
		success_ids = []
		failure_ids = []
		json_list.each do |json|
			code = json['code']
			details = json['details']
			id = details['id']
			if code == "SUCCESS" then
				success_ids[success_ids.length] = id
			else
				failure_ids[failure_ids.length] = id
			end
		end
		if failure_ids.length > 0 then
			print "There are #{failure_ids.length} failures :::: "
			return false, failure_ids
		else
			return true, failure_ids
		end
	end

	def delink_rl(rel_api_name, rel_id)
		# The document says: 
		# Module supported are 1) Campaigns 2) Productsod
		if @module_obj.nil? then
			return false
		end
		if @record_id.nil? then
			return false
		end

		is_supported_module = false		
		if (rel_api_name == "Campaigns" || rel_api_name == "Products") then
			is_supported_module = true
		end
		if !is_supported_module then
			print "Please check the module name, we only support Campaigns and Products."
			return false
		end
		related_record_obj = @module_obj.get_related_list_obj(rel_api_name)
		if related_record_obj.nil? then
			return false
		end
		#url = Constants::DEF_CRMAPI_URL + @module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + rel_api_name + Constants::URL_PATH_SEPERATOR + rel_id
		zclient = @module_obj.get_zclient
		url = Constants::ZOHOAPIS_URL + zclient.get_domain + Constants::V2_PATH + @module_name + Constants::URL_PATH_SEPERATOR + @record_id + Constants::URL_PATH_SEPERATOR + rel_api_name + Constants::URL_PATH_SEPERATOR + rel_id
		headers = zclient.construct_headers
		params = {}
		response = zclient.safe_delete(url, params, headers)
		result = is_delink_success(response)
		return result
	end

	def is_delink_success(response, rel_id)
		# Get a successful delink response 
		# Delink is not working, will have to talk to raghu :) 
		body = response.body
		list = Api_Methods._get_list(body, "data")
		list.each do |json|
			code = json['code']
			if code.downcase == "success" then
				return true
			end
		end
		return false
	end

	def get_module_obj
		return @module_obj
	end

	def set_module_obj(mod_obj)
		@module_obj = mod_obj
	end

	def get_required_fields
		if !@layout.nil? then
			return @layout.req_field_ids
		end
	end

	def get_required_fields1 #todo comment out
		if !@required_fields.empty? then
			return @required_fields
		else
			@fields.each do |id, f|
				if f.is_required then
					field_name = f.field_name
					@required_fields[@required_fields.length] = field_name
				end
			end
		end
	end

	def get(key)
		return @hash_values[key]
	end

	def set(field, value)
		valid = true
		if value.nil? then
			valid = false
			return false, "Value passed is nil"
		end
		length = field.get('length')
		if !length.nil? then
			l = length.to_i
			v_l = value.to_s.length
			if v_l > l then
				valid = false
				return false, "Length of the value is longer than maximum length"
			end
		end
		datatype = field.get_datatype
		if datatype == "website" then
			vs = value.to_s
			if vs =~ /^(http|https):\/\/|[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,6}(:[0-9]{1,5})?(\/.*)?$/ix then
				valid = true
			else
				valid = false
				return false, "Please provide a valid URL"
			end
		end
		if datatype == "email" then
			vs = value.to_s
			if vs =~ /\A[\w+\-.]+@[a-z\d\-]+(\.[a-z\d\-]+)*\.[a-z]+\z/i then
				valid = true
			else
				valid = false
				return false, "Please provide a valid email address"
			end
		end
		if valid then
			f_name = field.field_name
			if f_name == "Layout" then
				if value != @layout.id then
					return false, "Invalid layout id value given"
				end
			end
			current_value = self.get(f_name)
			if current_value.nil? then
				if !field.is_creatable then
					return false, "Field cannot be set while creation"
				end
				@added_fields[f_name] = current_value
				@hash_values[f_name] = value
			else
				if !field.is_editable then
					return false, "Field cannot be edited"
				end
				@modified_fields[f_name] = current_value
				@hash_values[f_name] = value
			end
			return true, "SUCCESS"
		end
	end

	def get_owner
		return @owner_id
	end

	def set_owner(id, user_data)
		profiles = @layout.profiles
		user_obj = user_data[id]
		confirm = user_obj["confirm"]
		if !confirm then
			return false, "User has not confirmed"
		end
		status = user_obj["status"]
		if status != "active" then
			return false, "User is not active yet"
		end
		u_profile_name = user_obj["profile"]["name"]
		u_profile_id = user_obj["profile"]["id"]
		valid = false
		profiles.each do |p_obj|
			p_id = p_obj["id"]
			if u_profile_id == p_id then
				valid = true
				break
			end
		end
		if !valid then
			return false, "User's profile does not have permission for this particular record's layout"
		end
		@owner_id = id
		return true, "SUCCESS"
	end

	def get_fieldobj(field_name)
		if @fields.nil? then
			return nil
		end
		result = nil
		@fields.each do |f_id, f_obj|
			f_name = f_obj.field_name
			if f_name == field_name then
				return f_obj
			end
		end
		return result
	end

	def setfield_byname(f_name, value)
		field = self.get_fieldobj(f_name)
		if field.nil? then
			return false, "No such field: #{f_name}, please refresh meta_data for '#{@module_name}' if its a newly created field."
		end
		return set(field, value)
	end

	def update(key, value, current_value="", data_type="")
		#The function returns two values, 
		#1) boolean - to say if the new value is over-written successfully
		#2) message - Result of the function in words
		message = "Value updated locally"

		if current_value.nil? then
			current_value = get(key)
		end
		if current_value.nil? then
			message = "Field cannot be found, try 'set' method to add a new key."
			return false, message
		elsif current_value.class != value.class then
			message = "Datatype mismatch, with current_value of the field. Please check the given value." 
			if !data_type.empty? 
				message = message+" Further info: field is of datatype "+data_type
			end
			return false, message
		else
			@modified_fields[key] = current_value
			@hash_values[key] = value
			return true, message
		end
	end

=begin
	def set_field_byname(key, value)
		field = @fields[key]
		data_type = ""
		if field.nil? then
			length = @unavailable_fields.length
			@unavailable_fields[length] = key
		elsif
			data_type = field.get_datatype
		end
		current_value = get(key)
		if current_value.nil? then
			@added_fields[key] = current_value
			@hash_values[key] = value
			return true
		else
			return update(key,value,current_value, data_type)
		end
	end
=end

	#Getters and setters :: Named in a fashion easier to understand for api users
	def delete
		is_record_marked_for_deletion = true
	end
	def undo_delete
		is_record_marked_for_deletion = false
	end

	def construct_upsert_hash
		if @module_obj.nil? then
			ZohoCRMClient.log("Please set module_obj for the record to continue")
			return false, nil
		end

		if @layout.nil? then
			@module_obj.default_layout
		end

		req_field_ids = self.get_required_fields
		all_fields = @module_obj.get_fields
		required_fields_available = true
		err_field_ids = []
		req_field_ids.each do |f_id|
			f_obj = all_fields[f_id]
			f_name = f_obj.field_name
			val = get(f_name)
			if val.nil? then
				required_fields_available = false
				err_field_ids[err_field_ids.length] = f_id
				ZohoCRMClient.debug_log("this field name has nil value : #{f_name}")
			end
		end

		if !required_fields_available then
			ZohoCRMClient.log("Values missing for following required fields, #{err_field_ids.inspect}")
			return false, err_field_ids
		end
		update_hash = {}
		if !self.record_id.nil? then
			update_hash['id'] = self.record_id
		end

		if !@owner_id.nil? then
			update_hash["Owner"] = @owner_id
		end

		@added_fields.each do |field_name, current_value| 
			update_hash[field_name] = get(field_name)
		end
		@modified_fields.each do |field_name, current_value|
			update_hash[field_name] = get(field_name)
		end
		return true, update_hash
	end

	#Utility function below
	def construct_update_hash #Contains a lot of print statements: Please remove when the function is working properly
		#Check for id presence when you are writing this function
		#If there's no id then you just have to no include it in the final update_hash
		if @module_obj.nil? then
			ZohoCRMClient.log("Please set module_obj for the record to continue")
			return false, nil
		end

		if @layout.nil? then
			@layout = @module_obj.default_layout
		end

		update_hash = {}

		if !self.record_id.nil? then
			update_hash['id'] = self.record_id
		end

		if !@owner_id.nil? then
			update_hash['id'] = @owner_id
		end

		@added_fields.each do |field_name, current_value| 
			update_hash[field_name] = self.get(field_name)
		end
		@modified_fields.each do |field_name, current_value|
			update_hash[field_name] = self.get(field_name)
		end

		if update_hash.size > 1 then
			return true, update_hash
		else
			return false, {}
		end
	end

	def record_errors(record_obj)
		temp_list = record_obj.keys
		@error_fields_lastupdate = @fields_sent_lastupdate - temp_list
		@update_cycle_complete = true
	end
	def get_errorfields_lastupdate
		if @update_cycle_complete then
			return @error_fields_lastupdate
		end
	end
	def check_fields
		res = false
		if @hash_values.empty? then
			return false
		else
			fieldlist = self.get_field_list
			returned_fieldlist = @hash_values.keys
			l1 = fieldlist.length
			l2 = returned_fieldlist.length
			if l2 > l1
				res = true 
			else
				res = false
			end
		end
		return res
	end

	def get_field_list
		res = []
		@fields.each do |field_id, field_obj|
			res[res.length] = field_obj.field_name
		end
		return res
	end
	def module_name
		return @module_name
	end
	def record_id
		return @record_id
	end
	private :update
end