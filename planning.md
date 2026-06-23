# Planning — GTA Santos

---

## Parte 1: Alturas de prédios para o efeito 2.5D

### Objetivo

Enriquecer cada prédio com **altura** e **área** para o efeito 2.5D (volume + parallax).
Sem 3D real. Tudo com fonte gratuita.

| Dado | Fonte | Motivo |
|---|---|---|
| Footprint (polígono) | Open Buildings V3 (Google) | Muito mais cobertura que OSM em Santos |
| Altura | Open Buildings 2.5D Temporal V1 — 2023 (GEE) | Raster 4m derivado de Sentinel-2 |
| Área | Calculada do polígono em projeção UTM | Não precisa baixar de fora |
| Correções de posição | `build/corrections.json` aplicado na Fase 3 | Alguns polígonos V3 aparecem deslocados |

> **Por que V3 e não OSM para footprint?** O V3 tem muito mais edificações que o OSM em Santos.
> A desvantagem é que alguns polígonos aparecem levemente deslocados (prédio no meio da rua).
> Isso é corrigível manualmente via arquivo de correções sem reprocessar tudo.

### Coordenadas do mapa

```
bbox: lat [-23.995, -23.905]  lon [-46.380, -46.285]
mapa: 8000 x 8292 px  (pre-ESCALA)
ESCALA = 15.0  (1 px pre-ESCALA aprox 1 metro)

Conversao lon/lat -> jogo:
  x = (lon - (-46.380)) / (-46.285 - (-46.380)) * 8000 * 15.0
  y = (1 - (lat - (-23.995)) / (-23.905 - (-23.995))) * 8292 * 15.0
```

---

### Fase 0 — Pre-requisitos [MANUAL, uma vez]

1. Ter (ou criar) uma conta Google.
2. Registrar no Earth Engine (gratuito):
   https://earthengine.google.com/ -> "Get Started" -> "Register a Noncommercial project".
3. Criar/escolher um Google Cloud Project gratuito e anotar o **Project ID**
   (ex.: `santos-driver-gee`).

> Sem esses tres itens, as Fases 1 e 2 nao rodam.

---

### Fase 1 — Baixar footprints Open Buildings V3 [MANUAL auth + CLI]

**Script:** `fase1_footprints.py`

**Pre-requisito [MANUAL]:**
```bash
source .venv/bin/activate
earthengine authenticate       # abre browser, login Google, cola codigo
```

**Executar:**
```bash
EE_PROJECT=santos-driver-gee python3 fase1_footprints.py
```

**O que faz:**
1. Conecta ao GEE com o Project ID informado.
2. Tenta carregar Open Buildings V3 (`GOOGLE/Research/open-buildings/v3/polygons`).
   Se V3 nao estiver no catalogo GEE, tenta V2, depois V1, e avisa qual foi usado.
3. Filtra pelo bbox de Santos (`confidence >= 0.65`).
4. Exporta em lotes de 200 features para evitar timeout.
5. Salva `build/footprints_v3.geojson` com campos:
   - `v3_idx`: indice sequencial (chave de join)
   - `v3_id`: plus code ou ID do GEE
   - `confidence`: score de confianca do V3
   - `area_m2_v3`: area reportada pelo V3 (para comparar com calculo UTM)

**Validacao:** arquivo abre no QGIS/geojson.io, features dentro do bbox, confidence entre 0.65-1.0.

---

### Fase 2 — Extrair alturas no GEE [CLI]

**Script:** `fase2_gee_alturas.py`

**Executar** (mesma sessao autenticada da Fase 1):
```bash
EE_PROJECT=santos-driver-gee python3 fase2_gee_alturas.py
```

**O que faz:**
1. Carrega `build/footprints_v3.geojson`.
2. Carrega Open Buildings 2.5D Temporal V1
   (`GOOGLE/Research/open-buildings-temporal/v1`), filtra 2023, seleciona banda `building_height`.
3. `reduceRegions` com `ee.Reducer.mean()` em escala 4m sobre cada footprint V3.
4. Exporta `build/alturas_gee.geojson` com campos: `v3_idx`, `height_2p5d`.

Se a exportacao for via `toDrive` (volumes grandes), o arquivo precisa ser baixado
manualmente do Google Drive e colocado em `build/alturas_gee.geojson`.

---

### Fase 3 — Mesclar + correcoes + converter para o jogo [CLI]

**Script:** `fase3_mesclar.py`

**Executar:**
```bash
python3 fase3_mesclar.py
```

**Cascata de fallback para altura:**
1. `height_2p5d` do GEE (se > 2m)
2. `osm_height` tag (se existir no V3)
3. `osm_levels * 3.0` (se existir)
4. Default por tipo de edificio: `house/residential` 6m, `apartments` 24m,
   `commercial/retail` 8m, `industrial/warehouse` 7m, generico 8m.

**Mecanismo de correcoes (`build/corrections.json`):**

Cada edificio problematico recebe uma entrada. Tres operacoes possiveis:

```json
{
  "42": {
    "tipo": "offset",
    "delta_lon": 0.00008,
    "delta_lat": -0.00005
  },
  "137": {
    "tipo": "substituir",
    "poly_lonlat": [[-46.334, -23.931], [-46.333, -23.931], [-46.333, -23.932], [-46.334, -23.931]]
  },
  "291": {
    "tipo": "remover"
  }
}
```

A chave e o `v3_idx` do edificio. O script le esse arquivo antes de gerar a saida e
aplica as correcoes. Se o arquivo nao existir, pula silenciosamente.

**Como identificar edificios para corrigir:**
- Abrir `build/footprints_v3.geojson` no QGIS com uma camada de fundo (OSM ou satelite)
- Edificios deslocados ficam visivelmente no meio de ruas
- Anotar o `v3_idx` do edificio (campo nas propriedades do QGIS)
- Editar `build/corrections.json` e rodar `fase3_mesclar.py` novamente

**Como corrigir visualmente no QGIS (alternativa ao offset manual):**
1. QGIS -> Layer -> Add Layer -> Add Vector Layer -> `build/footprints_v3.geojson`
2. Adicionar basemap OSM: Web -> QuickMapServices -> OSM -> Standard
3. Selecionar a camada V3 -> Toggle Editing (lapis)
4. Selecionar o edificio deslocado -> Move Feature
5. Arrastar para a posicao correta
6. Save Layer Edits -> Export como novo GeoJSON
7. Um script diff extrai as mudancas e gera `corrections.json` automaticamente

**Saida:** `maps/santos_buildings_2p5d.json`

```json
{
  "predios": [
    {
      "v3_idx": 0,
      "poly_game": [[x, y], ...],
      "poly_lonlat": [[-46.33, -23.93], ...],
      "altura_m": 12.5,
      "andares": 4,
      "area_m2": 320.0,
      "altura_fonte": "2p5d",
      "confidence": 0.87
    }
  ]
}
```

> Nao sobrescreve `maps/santos.json`. Arquivo novo e independente.

---

### Fase 4 — Relatorio [CLI]

**Script:** `fase4_relatorio.py`

```bash
python3 fase4_relatorio.py
```

Gera `build/RELATORIO_alturas.md` com: total de predios, distribuicao de fontes de altura,
stats de altura e area, bbox efetivo, tipos de edificio mais comuns.

---

### Arquivos gerados

```
build/
  footprints_v3.geojson       <- Fase 1: poligonos Open Buildings V3
  alturas_gee.geojson         <- Fase 2: alturas brutas do GEE
  corrections.json            <- correcoes manuais (criado pelo usuario)
  RELATORIO_alturas.md        <- Fase 4: resumo estatistico

maps/
  santos_buildings_2p5d.json  <- Fase 3: saida para o jogo
```

---

### Resumo manual vs CLI

| Fase | Passo | Quem |
|---|---|---|
| 0 | Conta GEE + Cloud Project | **MANUAL** |
| 1 | `earthengine authenticate` | **MANUAL** |
| 1 | Download V3 polygons filtrado por bbox | CLI |
| 2 | Extracao de alturas 2.5D | CLI |
| 2 | Baixar do Drive se exportou via toDrive | **MANUAL** |
| 3 | Mesclar, correcoes, converter para jogo | CLI |
| 3 | Identificar e corrigir poligonos deslocados (QGIS) | **MANUAL** (iterativo) |
| 4 | Relatorio final | CLI |

---

### Licencas

- **Open Buildings V3 e 2.5D Temporal** — Google, CC BY 4.0. Creditar Google no jogo.
- **OpenStreetMap** — ODbL (santos.json ainda em uso para ruas).
- Confirmar nomes de dataset/banda no catalogo do GEE no momento da execucao.

---

---

## Parte 2: Multiplayer com Supabase

### Objetivo

Jogadores entram no jogo informando onde estao (rua digitada ou GPS automatico do browser).
Cada jogador aparece como sprite no mapa de Santos. Posicoes sincronizadas em tempo real.

### Fluxo

```
Jogador abre o jogo (HTML5)
  -> digita nome + rua  OU  clica "Usar minha localizacao" (GPS)
  -> geocodifica via Nominatim -> lat/lon
  -> converte lat/lon -> coordenada do jogo
  -> salva no Supabase + recebe outros jogadores
  -> renderiza outros como sprites no mapa
```

---

### Banco de dados (Supabase)

```sql
create table players (
  id          text primary key,
  nome        text not null,
  lat         double precision,
  lon         double precision,
  game_x      double precision,
  game_y      double precision,
  updated_at  timestamptz default now()
);

alter table players enable row level security;
create policy "leitura publica"  on players for select using (true);
create policy "escrita propria"  on players for insert with check (true);
create policy "update proprio"   on players for update using (true);
create policy "delete proprio"   on players for delete using (true);
```

Jogadores inativos: filtrar no SELECT com `updated_at > now() - interval '5 minutes'`.

---

### Geocodificacao (Nominatim)

```
GET https://nominatim.openstreetmap.org/search
    ?q=<endereco>+Santos+SP+Brasil
    &format=json&limit=1&bounded=1
    &viewbox=-46.38,-23.995,-46.285,-23.905
```

User-Agent obrigatorio: `"santos-gta/1.0"`. Rate limit 1 req/s, so no login.

### GPS automatico (Godot HTML5)

```gdscript
JavaScript.eval("""
  navigator.geolocation.getCurrentPosition(
    function(pos) { window._gps_lat = pos.coords.latitude; window._gps_lon = pos.coords.longitude; window._gps_ok = true; },
    function(err) { window._gps_ok = false; },
    { timeout: 8000 }
  );
""")
```

---

### Arquivos novos no Godot

```
scenes/Lobby.tscn         <- tela de entrada (nome + endereco/GPS)
scenes/RemotePlayer.tscn  <- sprite de jogador remoto
scripts/lobby.gd          <- geocodificacao + validacao de bbox
scripts/multiplayer.gd    <- autoload: sync de posicao com Supabase
scripts/remote_player.gd  <- interpola posicao do jogador remoto
```

### multiplayer.gd (Autoload)

```gdscript
const SUPABASE_URL   = "https://<projeto>.supabase.co"
const ANON_KEY       = "<anon_key_publica>"
const INTERVALO_SYNC = 1.5

# Ciclo: UPSERT posicao propria + GET outros jogadores ativos
# Emite sinal outros_jogadores_atualizados(lista)
```

### remote_player.gd

```gdscript
func _process(delta):
    position = position.linear_interpolate(_alvo, 8.0 * delta)  # esconde latencia

func atualizar(dados):
    _alvo = Vector2(dados["game_x"], dados["game_y"]) * 15.0
```

### Integracao no main.gd

```gdscript
func _on_outros_atualizados(lista):
    var ids_recebidos = {}
    for dados in lista:
        var id = dados["id"]
        ids_recebidos[id] = true
        if not _remotos.has(id):
            var node = preload("res://scenes/RemotePlayer.tscn").instance()
            add_child(node)
            _remotos[id] = node
        _remotos[id].atualizar(dados)
    for id in _remotos.keys():
        if not ids_recebidos.has(id):
            _remotos[id].queue_free()
            _remotos.erase(id)
```

---

### Ordem de implementacao

- [ ] 1. Criar tabela no Supabase e testar com curl
- [ ] 2. `multiplayer.gd` — upsert e fetch funcionando
- [ ] 3. `Lobby.tscn` + `lobby.gd` — digitacao + geocodificacao
- [ ] 4. Botao GPS via `JavaScript.eval`
- [ ] 5. `RemotePlayer.tscn` + `remote_player.gd`
- [ ] 6. Integracao no `main.gd`
- [ ] 7. Mudar `main_scene` para Lobby
- [ ] 8. Re-exportar HTML5 e testar com duas abas
