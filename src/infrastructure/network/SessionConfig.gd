extends RefCounted
class_name SessionConfig

static var selected_mode: String = "offline_ai"
static var auto_requeue_on_death: bool = true
static var requeue_on_lobby_entry: bool = false

static var network_enabled: bool = false
static var network_role: String = "offline"
static var transport: String = "local"
static var host: String = "127.0.0.1"
static var port: int = 7000
static var max_players: int = 10
static var session_id: String = "local_session"
static var player_id: String = "player"
static var local_actor_id: String = "player"
static var net_log: bool = false
static var match_id: String = ""
static var match_token: String = ""

static func configure_offline(mode_name: String = "offline_ai") -> void:
	selected_mode = mode_name
	network_enabled = false
	network_role = "offline"
	transport = "local"
	host = "127.0.0.1"
	port = 7000
	max_players = 10
	local_actor_id = "player"
	match_id = ""
	match_token = ""

static func configure_online_client(
	mode_name: String,
	target_host: String,
	target_port: int,
	session: String,
	player: String,
	assigned_match_id: String = "",
	assigned_match_token: String = ""
) -> void:
	selected_mode = mode_name
	network_enabled = true
	network_role = "client"
	transport = "enet"
	host = target_host
	port = target_port
	session_id = session
	player_id = player
	local_actor_id = "player"
	match_id = assigned_match_id
	match_token = assigned_match_token
