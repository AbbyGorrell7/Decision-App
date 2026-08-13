extends Node
@onready var line_edit: LineEdit = $UILayout/LineEdit
@onready var reset_button: Button = $UILayout/Button2
@onready var item_list: ItemList = $UILayout/ItemList
@onready var generate_button: Button = $UILayout/Button
@onready var decision_popup: AcceptDialog = $DecisionPopup
@onready var http_request: HTTPRequest = $HTTPRequest
@onready var ip_request: HTTPRequest = $IPRequest

var choices: Array[String] = []
var current_lat: float = 0.0
var current_lon: float = 0.0
var search_keyword: String = ""
func _ready() -> void: 
	line_edit.grab_focus()
	generate_button.disabled = true
	generate_button.text = "Loading Locations..."
	get_browser_location()

func _on_line_edit_text_submitted(new_text: String) -> void:
	if new_text.strip_edges() != "":
		choices.append(new_text.strip_edges())
		item_list.add_item(new_text.strip_edges())
		line_edit.clear()

func _on_generate_button_pressed() -> void:
	if choices.size() == 0:
		print("Button pressed! Browser is authorized")
		if current_lat == 0.0 and current_lon == 0.0:
			print("Still waiting on broser location")
			return
		fetch_local_restaurants()
		return
	
	generate_button.disabled = true
	var total_flashes = 15
	var flash_delay = 0.05 
		
	for i in range(total_flashes):
		var dummy_index = i % choices.size()
		item_list.select(dummy_index)
			
		await get_tree().create_timer(flash_delay).timeout
			
		if i > 10:
			flash_delay += 0.05 
			
	var random_index = randi() % choices.size()
	item_list.select(random_index)
		
	var final_choice = choices[random_index].to_upper()
		
	decision_popup.title = "Decision Made!"
	decision_popup.dialog_text = "The Universe Has Decided:\n" + final_choice
	decision_popup.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	decision_popup.popup_centered()
		
	generate_button.disabled = false


func _on_reset_button_pressed() -> void:
	choices.clear()
	item_list.clear()
	decision_popup.title = "Reset Complete"
	decision_popup.dialog_text = "You May Now Start A New List"
	decision_popup.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	decision_popup.popup_centered()


func _on_item_list_item_activated(index: int) -> void:
	var removed_item = choices[index].to_upper()
	choices.remove_at(index)
	item_list.remove_item(index)
	decision_popup.title = "Removed"
	decision_popup.dialog_text = removed_item + " Has Been Removed"
	decision_popup.get_label().horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	decision_popup.popup_centered()

func get_browser_location() -> void:
	fetch_location_by_ip()

func fetch_location_by_ip() -> void:
	var url = "https://ipapi.co/json/"
	if ip_request.request_completed.is_connected(_on_ip_location_received):
		ip_request.request_completed.disconnect(_on_ip_location_received)
	ip_request.request_completed.connect(_on_ip_location_received)
	ip_request.request(url)

func _on_ip_location_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var json = JSON.new()
	json.parse(body.get_string_from_utf8())
	var data = json.get_data()
	if data and data.has("latitude"):
		current_lat = data["latitude"]
		current_lon = data["longitude"]
		print("Backup success: Found your location!")
		generate_button.disabled = false
		generate_button.text = "Find Places Around Me"
	else:
		print("Backup failed")
		current_lat = 40.0640
		current_lon = -80.7210
		generate_button.disabled = false
		generate_button.text = "Find Places Around Me"
	
func _on_browser_location_js_bridge(args: Array) -> void:
	current_lat = args[0]
	current_lon = args[1]
	print("Success: Godot engine variables updated good!")
	generate_button.disabled = false
	generate_button.text = "Find Places Around Me"

func _on_browser_location_received(args: Array) -> void:
	var position = args[0]
	var coords = position.coords
	var lat = coords.latitude
	var lon = coords.longitude
	print("---HYPER-ACCURATE BROWSER LOCATION RECEIVED---")
	print("Latitude: ", lat)
	print("Longitude: ", lon)

func fetch_local_restaurants() -> void:
	search_keyword = line_edit.text.strip_edges()
	if search_keyword == "":
		search_keyword = "food"
		
	print("Searching for '", search_keyword, "' around: ", current_lat, ", ", current_lon)
	
	# Translate searches into clean keywords Nominatim understands
	var query_param = search_keyword
	var lower_key = search_keyword.to_lower()
	if "gas" in lower_key:
		query_param = "gas station"
	elif "food" in lower_key or "restaurant" in lower_key:
		query_param = "restaurant"
	elif "coffee" in lower_key or "cafe" in lower_key:
		query_param = "cafe"
	elif "park" in lower_key:
		query_param = "park"

	# Build a 10-mile search box around the user's latitude and longitude
	var delta = 0.15
	var min_lon = current_lon - delta
	var max_lat = current_lat + delta
	var max_lon = current_lon + delta
	var min_lat = current_lat - delta
	
	var url = "https://nominatim.openstreetmap.org/search?q=%s&format=json&viewbox=%f,%f,%f,%f&bounded=1&limit=15" % [
		query_param.uri_encode(), min_lon, max_lat, max_lon, min_lat
	]
	
	if http_request.request_completed.is_connected(_on_restaurant_data_received):
		http_request.request_completed.disconnect(_on_restaurant_data_received)
	
	http_request.request_completed.connect(_on_restaurant_data_received)
	http_request.timeout = 5.0 # Fast 5-second timeout
	
	var headers = PackedStringArray([
		"User-Agent: DecisionApp/1.0 (GodotEngineStudentProject)"
	])
	
	var error = http_request.request(url, headers)
	if error != OK:
		print("HTTP Request failed to start - loading fallback dataset.")
		_load_fallback_dataset()

func _on_restaurant_data_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var raw_text = body.get_string_from_utf8()
	print("Network response code: ", response_code)
	
	var json = JSON.new()
	var parse_err = json.parse(raw_text)
	var loaded_any = false
	
	if parse_err == OK:
		var response = json.get_data()
		if response and response is Array and response.size() > 0:
			choices.clear()
			item_list.clear()
			for place in response: 
				if place.has("display_name"):
					var full_name = place["display_name"]
					var spot_name = full_name.split(",")[0].strip_edges()
					if spot_name.to_lower() == "gas" or spot_name.to_lower() == "gas station":
						var parts = full_name.split(",")
						if parts.size() > 1:
							spot_name = parts[1].strip_edges()
					if not choices.has(spot_name):
						choices.append(spot_name)
						item_list.add_item(spot_name)
			if choices.size() > 0:
				loaded_any = true
				print("Success: Loaded ", choices.size(), " live spots form Nominatim!")
	if choices.size() < 3:
		print("Fewer than 3 spots found. Activating Local Dataset Fallback!")
		_load_fallback_dataset()

func _load_fallback_dataset() -> void:
	choices.clear()
	item_list.clear()
	var search_term = line_edit.text.strip_edges().to_lower()
	var fallback_spots: Array[String] = []
		
	if "gas" in search_term: 
		fallback_spots = ["Sheetz", "Speedway", "BP", "Circle K", "Exxon", "GetGo"]
	elif "park" in search_term: 
		fallback_spots = ["Community Park", "Memorial Dog Park", "Riverfront Trail", "State Park Reserve", "Oakridge Nature Center"]
	elif "coffee" in search_term or "cafe" in search_term:
		fallback_spots = ["Starbucks", "Dunkin'", "Local Roasters Cafe", "Court Street Coffee", "Peet's Coffee"]
	else:
		fallback_spots = ["Chipotle", "Domino's Pizza", "Taco Bell", "Wendy's", "Subway", "Panda Express", "Panera Bread"]
	
	for spot in fallback_spots:
		choices.append(spot)
		item_list.add_item(spot)
	
	print("Fallback Success: Populated wheel with ", choices.size(), " locations!")
