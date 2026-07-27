extends Node

const MainMenu = preload("res://scripts/ui/main_menu.gd")
const SkirmishSetup = preload("res://scripts/ui/skirmish_setup.gd")
const CampaignMenu = preload("res://scripts/ui/campaign_menu.gd")
const LANLobby = preload("res://scripts/ui/lan_lobby.gd")
const SettingsMenu = preload("res://scripts/ui/settings_menu.gd")
const RTSMatch = preload("res://scripts/game/rts_match.gd")
const RA2DatabaseBrowser = preload("res://scripts/ui/ra2_database_browser.gd")

var current_screen

func _ready():
    show_main_menu()

func _replace_screen(next_screen):
    if is_instance_valid(current_screen):
        current_screen.queue_free()
    current_screen = next_screen
    add_child(current_screen)

func show_main_menu():
    var screen = MainMenu.new()
    screen.skirmish_requested.connect(show_skirmish_setup)
    screen.campaign_requested.connect(show_campaign_menu)
    screen.settings_requested.connect(show_settings_menu)
    screen.lan_requested.connect(show_lan_lobby)
    screen.ra2_database_requested.connect(show_ra2_database)
    screen.quit_requested.connect(_quit_game)
    _replace_screen(screen)

func show_ra2_database():
    var screen = RA2DatabaseBrowser.new()
    screen.back_requested.connect(show_main_menu)
    _replace_screen(screen)

func show_lan_lobby():
    var screen = LANLobby.new()
    screen.back_requested.connect(show_main_menu)
    screen.start_requested.connect(start_match)
    _replace_screen(screen)

func show_settings_menu():
    var screen = SettingsMenu.new()
    screen.back_requested.connect(show_main_menu)
    _replace_screen(screen)

func show_skirmish_setup():
    var screen = SkirmishSetup.new()
    screen.back_requested.connect(show_main_menu)
    screen.start_requested.connect(start_match)
    _replace_screen(screen)

func show_campaign_menu():
    var screen = CampaignMenu.new()
    screen.back_requested.connect(show_main_menu)
    screen.start_requested.connect(start_match)
    _replace_screen(screen)

func start_match(config):
    GameConfig.current_match = config.duplicate(true)
    var match_scene = RTSMatch.new()
    match_scene.match_config = GameConfig.current_match
    match_scene.exit_to_menu.connect(show_main_menu)
    _replace_screen(match_scene)

func _quit_game():
    get_tree().quit()
