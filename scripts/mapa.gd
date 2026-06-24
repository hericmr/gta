# mapa.gd — Mapa da cidade com posição do player (toggle com M)
extends CanvasLayer

const CAMINHO_JSON = "res://maps/santos.json"
const MAPA_LARG    = 8960.0
const MAPA_ALT     = 11520.0
const PADDING      = 40.0

# Cores
const COR_FUNDO    = Color(0.05, 0.07, 0.10, 0.93)
const COR_RUA      = Color(0.55, 0.55, 0.60, 0.70)
const COR_RUA_MAIN = Color(0.85, 0.85, 0.90, 0.85)
const COR_PLAYER   = Color(1.00, 0.20, 0.20, 1.00)
const COR_TEXTO    = Color(1.00, 1.00, 1.00, 0.80)

var _dados       = null
var _player_pos  = Vector2.ZERO
var _stream      = null   # referência ao satelite_stream para converter coords
var _pulso       = 0.0
var _visivel     = false

onready var _desenho: Control    = $Desenho
onready var _label_coords: Label = $LabelCoords
onready var _label_hint: Label   = $LabelHint


func _ready() -> void:
    layer   = 10
    visible = false
    _carregar_dados()


func _carregar_dados() -> void:
    var arq = File.new()
    if not arq.file_exists(CAMINHO_JSON):
        return
    arq.open(CAMINHO_JSON, File.READ)
    _dados = parse_json(arq.get_as_text())
    arq.close()


# Chamado por main.gd a cada frame quando o mapa está visível
func atualizar(pos_jogo: Vector2, stream) -> void:
    _player_pos = pos_jogo
    _stream     = stream


func _process(delta: float) -> void:
    if not _visivel:
        return
    if Input.is_action_just_pressed("ui_cancel"):
        toggle()
        return
    _pulso += delta * 3.0
    _desenho.update()

    if _stream and _player_pos != Vector2.ZERO:
        var pos_pre = _player_pos / 15.0
        var lat = _stream._pos_para_lat(pos_pre.y)
        var lon = _stream._pos_para_lon(pos_pre.x)
        _label_coords.text = "lat %.5f   lon %.5f" % [lat, lon]
    else:
        _label_coords.text = ""


func toggle() -> void:
    _visivel = !_visivel
    visible  = _visivel


# ── Desenho do mapa ────────────────────────────────────────────────────────────

func _calc_escala(vp: Vector2) -> Dictionary:
    var area_x = vp.x - PADDING * 2
    var area_y = vp.y - PADDING * 2
    var escala = min(area_x / MAPA_LARG, area_y / MAPA_ALT)
    var larg   = MAPA_LARG * escala
    var alt    = MAPA_ALT  * escala
    return {
        "e":  escala,
        "ox": (vp.x - larg) / 2.0,
        "oy": (vp.y - alt)  / 2.0,
    }


func _mapa_para_tela(px: float, py: float, s: Dictionary) -> Vector2:
    return Vector2(px * s.e + s.ox, py * s.e + s.oy)


func desenhar(canvas: CanvasItem) -> void:
    if not _dados:
        return

    var vp = _desenho.get_viewport_rect().size
    var s  = _calc_escala(vp)

    # Fundo
    canvas.draw_rect(Rect2(Vector2.ZERO, vp), COR_FUNDO)

    # Borda do mapa
    var r = Rect2(s.ox, s.oy, MAPA_LARG * s.e, MAPA_ALT * s.e)
    canvas.draw_rect(r, Color(1, 1, 1, 0.08))
    canvas.draw_rect(r, Color(1, 1, 1, 0.20), false, 1.0)

    # Ruas
    for rua in _dados["ruas"]:
        var pts  = rua["pontos"]
        var larg = float(rua.get("largura", 4))
        var cor  = COR_RUA_MAIN if larg >= 8 else COR_RUA
        var w    = clamp(larg * s.e * 0.5, 0.4, 2.5)
        for i in range(len(pts) - 1):
            var p1 = _mapa_para_tela(pts[i][0],   pts[i][1],   s)
            var p2 = _mapa_para_tela(pts[i+1][0], pts[i+1][1], s)
            canvas.draw_line(p1, p2, cor, w)

    # Player
    var pos_pre  = _player_pos / 15.0
    var pos_tela = _mapa_para_tela(pos_pre.x, pos_pre.y, s)

    # Círculo pulsante externo
    var raio_ext = 6.0 + sin(_pulso) * 3.0
    canvas.draw_circle(pos_tela, raio_ext, Color(1, 0.2, 0.2, 0.35))
    # Círculo sólido
    canvas.draw_circle(pos_tela, 5.0, COR_PLAYER)
    # Ponto central branco
    canvas.draw_circle(pos_tela, 2.0, Color(1, 1, 1, 0.9))

    # Cruz de direção
    var sz = 10.0
    canvas.draw_line(pos_tela - Vector2(sz, 0), pos_tela + Vector2(sz, 0),
                     Color(1, 1, 1, 0.6), 1.0)
    canvas.draw_line(pos_tela - Vector2(0, sz), pos_tela + Vector2(0, sz),
                     Color(1, 1, 1, 0.6), 1.0)
