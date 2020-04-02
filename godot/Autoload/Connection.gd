extends Node

const CONFIG := "user://config.ini"
const KEY := "defaultkey"

enum OpCodes {
	UPDATE_POSITION = 1,
	REQUEST_POSITION,
	UPDATE_INPUT
}

signal connected
signal disconnected
signal error(error)
signal presences_changed
signal position_updated(id, position)

var session: NakamaSession
var client := Nakama.create_client(KEY, "127.0.0.1", 7350, "http")
var error_message := ""
var socket: NakamaSocket
var username: String setget , _get_username
var presences := {}
var world_id: String


func register(email: String, password: String, _username: String) -> int:
	var new_session: NakamaSession = yield(client.authenticate_email_async(email, password, _username, true), "completed")
	
	var parsed := _parse_exception(new_session)
	if parsed == OK:
		session = new_session
	return parsed


func login(email: String, password: String) -> int:
	var new_session: NakamaSession = yield(client.authenticate_email_async(email, password, null, false), "completed")
	
	var parsed := _parse_exception(new_session)
	if parsed == OK:
		session = new_session
	return parsed


func connect_to_server() -> int:
	socket = Nakama.create_socket_from(client)
	
	var result: NakamaAsyncResult = yield(socket.connect_async(session), "completed")
	var parsed := _parse_exception(result)
	if parsed == OK:
		#warning-ignore: return_value_discarded
		socket.connect("connected", self, "_on_socket_connected")
		#warning-ignore: return_value_discarded
		socket.connect("closed", self, "_on_socket_closed")
		#warning-ignore: return_value_discarded
		socket.connect("received_error", self, "_on_socket_error")
		#warning-ignore: return_value_discarded
		socket.connect("received_match_presence", self, "_on_new_match_presence")
		#warning-ignore: return_value_discarded
		socket.connect("received_match_state", self, "_on_Received_Match_State")
	
	return parsed


func save_email(email: String) -> void:
	var file := ConfigFile.new()
	#warning-ignore: return_value_discarded
	file.load(CONFIG)
	file.set_value("connection", "last_email", email)
	#warning-ignore: return_value_discarded
	file.save(CONFIG)


func get_last_email() -> String:
	var file := ConfigFile.new()
	#warning-ignore: return_value_discarded
	file.load(CONFIG)
	
	if file.has_section_key("connection", "last_email"):
		return file.get_value("connection", "last_email")
	else:
		return ""


func clear_last_email() -> void:
	var file := ConfigFile.new()
	#warning-ignore: return_value_discarded
	file.load(CONFIG)
	file.set_value("connection", "last_email", "")
	#warning-ignore: return_value_discarded
	file.save(CONFIG)


func join_world() -> int:
	if not world_id:
		var world: NakamaAPI.ApiRpc = yield(client.rpc_async(session, "get_world_id", ""), "completed")
		var parsed := _parse_exception(world)
		if not parsed == OK:
			return parsed
		world_id = world.payload
	
	var match_join_result: NakamaRTAPI.Match = yield(socket.join_match_async(world_id), "completed")
	var parsed := _parse_exception(match_join_result)
	if parsed == OK:
		for presence in match_join_result.presences:
			presences[presence.user_id] = presence
	
	return parsed


func request_position_update(id_requested: String) -> void:
	var payload := {id= id_requested}
	socket.send_match_state_async(world_id, OpCodes.REQUEST_POSITION, JSON.print(payload))


func send_position_update(position: Vector2) -> void:
	var payload := {id=session.user_id, pos=[position.x, position.y]}
	socket.send_match_state_async(world_id, OpCodes.UPDATE_POSITION, JSON.print(payload))


func _parse_exception(result: NakamaAsyncResult) -> int:
	if result.is_exception():
		var exception: NakamaException = result.get_exception()
		error_message = exception.message
		return exception.status_code
	else:
		return OK


func _on_socket_connected() -> void:
	emit_signal("connected")


func _on_socket_closed() -> void:
	emit_signal("disconnected")
	socket.disconnect("connected", self, "_on_socket_connected")
	socket.disconnect("closed", self, "_on_socket_closed")
	socket.disconnect("received_error", self, "_on_socket_error")


func _on_socket_error(error: String) -> void:
	emit_signal("error", error)


func _get_username() -> String:
	return session.username


func _on_new_match_presence(new_presences: NakamaRTAPI.MatchPresenceEvent) -> void:
	for leave in new_presences.leaves:
		#warning-ignore: return_value_discarded
		presences.erase(leave.user_id)
	for join in new_presences.joins:
		if not join.user_id == session.user_id:
			presences[join.user_id] = join
	emit_signal("presences_changed")


func _on_Received_Match_State(match_state: NakamaRTAPI.MatchData) -> void:
	var code := match_state.op_code
	var raw := match_state.data
	match code:
		1:
			var decoded := JSON.parse(raw)
			var result: Dictionary = decoded.result
			var position := Vector2(result.pos[0], result.pos[1])
			var id: String = result.id
			emit_signal("position_updated", id, position)
