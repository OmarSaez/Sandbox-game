# Registro Maestro y Documentación Técnica de NPCs — Sandbox Ultra

Este documento registra todos los NPCs implementados en el juego, su identificador técnico en código, su ID de material, sus estadísticas exactas de vida, daño, alcance, enfriamiento (*cooldown*), movimiento, saltos y comportamientos de IA. Sirve como tabla de referencia central para equilibrar (*balancear*) unidades existentes y añadir nuevos personajes.

---

## 1. Tabla Comparativa General de NPCs

| Nombre en Juego | Nombre Técnico (`type`) | ID Material | Facción | Tamaño (`W×H`) | Vida Base (`HP`) | Daño por Ataque | Tipo de Ataque | Alcance | Cooldown | Velocidad Mov. |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- | :---: | :---: | :---: |
| **⚔️ Guerrero** | `"warrior"` | `1000` | Equipos (`0..3`) | `5 × 7` | `85 – 115` *(~100)* | `15.0 × atk_dmg` *(12–18.75)* | Cuerpo a cuerpo (+5% variante fuego) | `< 6 px` | `0.6 s` | Normal (`1 px/tick`, 20 Hz) |
| **🏹 Arquero** | `"archer"` | `1010` | Equipos (`0..3`) | `5 × 7` | `85 – 115` *(~100)* | `40.0 × atk_dmg` *(32–50)* | Proyectil balístico (`arrow`) | `50 – 120 px` | `1.1 – 1.5 s` | Normal (`1 px/tick`, 20 Hz) |
| **⛏️ Minero** | `"miner"` | `1020` | Equipos (`0..3`) | `5 × 8` | `85 – 115` *(~100)* | Excavación / Sabotaje TNT | Excavación de túneles + Piso TNT | Contacto | `0.75 – 3.0 s` | Excavación (`1 px` por ciclo) |
| **💊 Médico** | `"medic"` | `1040` | Equipos (`0..3`) | `5 × 7` | `85 – 115` *(~100)* | Cura `+15 a +35 HP` (`heal_power`) | Curación a aliados heridos | `< 25 px` | `1.0 s` *(0.8s Arcade)* | Normal (`1 px/tick`, 20 Hz) |
| **🧙 Mago** | `"mage"` | `1070` | Equipos (`0..3`) | `8 × 10` | `85 – 115` *(~100)* | `35.0 × atk_dmg` + Fuego + 5% Conversión | Bola de fuego (`fireball`) + Rescate | `35 – 110 px` | `1.8 s` *(1.5s Arcade)* | Normal (`1 px/tick`, `2 px` en rescate) |
| **🧟 Zombie** | `"zombie"` | `1050` (`1080`) | Sin bando (`-1`) | `5 × 7` | `85 – 115` *(~100)* | `15.0 × atk_dmg` + Infección | Cuerpo a cuerpo infeccioso | `< 6 px` | `0.8 s` *(0.5s Arcade)* | Lento (`1/3` ticks en patrulla) |
| **🧌 Zombie Tanque** | `"zombie_tank"` | `1060` (`1080`) | Sin bando (`-1`) | `6 × 9` | `280 – 320` *(~300)* | Melee `15.0` / Roca `75.0` en radio `18 px` | Melee pesado + Lanzar bloque (`thrown_rock`) | Melee `< 7 px` / Roca `35–150 px` | Melee `1.0 s` / Roca `2.5 s` | Muy lento (`1/4` ticks en patrulla) |
| **🦖 Dinosaurio** | `"dinosaurio"` | `1090` (`1080`) | Sin bando (`-1`) | `15 × 11` | `500 – 600` *(~550)* | `60.0 × atk_dmg` (`4×` daño melee) | Mordisco colosal cuerpo a cuerpo | `~13 px` desde centro | `0.6 s` | Normal (`1 px/tick`, 20 Hz) |
| **⚡ Zeus** | `"zeus"` | `1100` | Sin bando (`-1`) | `7 × 10` | `500` *(5× Guerrero)* | Rayo del cielo (`120.0` exp. radio `5 px` + electricidad) | Descarga de Rayo (`_strike_lightning_at`) | `25 – 140 px` | `1.8 s` *(1.5s Arcade)* | Normal (`1 px/tick`, 20 Hz) |

---

## 2. Parámetros Globales de Física, Saltos y Modificadores RPG

Todos los NPCs comparten el motor físico base en [`_process_npcs`](file:///c:/Users/omaez/Desktop/Proyectos/Sandbox-game/sandbox/scripts/sandbox/sandbox_grid.gd#L5486-L6578) (que corre a **20 ticks por segundo**, `npc_update_timer = 0.05s`) y reciben variaciones individuales al ser generados en [`_place_npc`](file:///c:/Users/omaez/Desktop/Proyectos/Sandbox-game/sandbox/scripts/sandbox/sandbox_grid.gd#L5204-L5344):

### 2.1 Variaciones Individuales al Spawnear (RPG Stats)
* **`atk_dmg` (Multiplicador de Daño)**: `0.80` a `1.25` ($\pm 25\%$ sobre el daño base).
* **`knockback_mult` (Fuerza de Empuje)**: `0.70` a `1.30`.
* **`cowardice` (Cobardía / Prob. de Huida)**: `0.15` a `0.45` (se evalúa cuando `hp <= 30% max_hp`).
* **`precision` (Desviación de Puntería)**: `-0.60` a `+0.60` (afecta la parábola vertical del Arquero).
* **`heal_power` (Potencia de Curación)**: `15.0` a `35.0` HP por pulso (usado por el Médico).
* **`is_fire_variant` (Variante Ígnea)**: `5%` de probabilidad de que sus ataques cuerpo a cuerpo o flechas generen fuego (`ID 3`).

### 2.2 Sistema de Saltos y Movilidad Vertical
* **Subida Automática de Escalones (*Step-Up*)**: Cualquier NPC que camina puede subir escalones de `1` a `3` píxeles de altura automáticamente sin perder velocidad (`dy in [0, -1, -2, -3]`).
* **Salto de Obstáculos Altos (`4` a `12` píxeles)**: Impulso físico `vy = -5.2`, `vx = dir * 3.4`.
* **Salto de Peligros (Lava, Ácido, Explosivos a $\le 5$ px)**: Si el charco mide $\le 20$ px de ancho, salta con `vy = -4.8`, `vx = dir * 3.6`.
* **Salto sobre Aliados**: En persecución (`vy = -3.5`, `vx = dir * 2.0`) o tras 5 choques en patrulla (`vy = -4.0`, `vx = dir * 2.5`).
* **Salto Anti-Atasco (`stuck_timer > 0.8s`)**: `vy = -4.5`, `vx = dir * 2.5` con emoji `🔨`.
* **Salto en Modo Controlado (Arcade 🎮)**: `vy = -5.5`, velocidad horizontal máxima `vx = ±2.1`.
* **Gravedad y Daño por Caída**:
  * Gravedad en el aire: `vy += 1.0` por tick (velocidad terminal `vy = 8.0`).
  * Daño por caída: Si `fall_depth >= 12` (o `>= 15` con impulso físico), recibe `(fall_depth - 10) * 1.5` de daño (`50%` reducido si es controlado por el jugador).

### 2.3 Bonificadores Especiales (Líder y Modo Arcade)
* **Promoción a Líder (`👑`)**: Si se reúnen `5` o más aliados del mismo equipo en un radio de `100 px` sin líder previo, uno asciende a Líder:
  * `max_hp *= 1.5` y `hp *= 1.5` (+50% de vida).
  * `knockback_mult *= 0.7` (30% más resistente al empuje).
  * Emite un aura de moral en `140 px` que reduce a la mitad el pánico ante desastres.
* **Modo Controlado por Jugador (Héroe Arcade 🎮)**:
  * Su vida mínima sube a `max(hp, 160.0)`.
  * Recibe `40%` menos daño cuerpo a cuerpo y `50%` menos daño por explosiones, caídas, ácido, fuego y electricidad.

### 2.4 Daño Ambiental (chequeado cada `0.5 s`)
* **Ácido (`ACID`)**: `-3.5 HP` por chequeo (puede transformar humanos en Zombie al bajar del 20% de vida o morir).
* **Fuego / Lava (`INCENDIARY`)**: `-1.2 HP` por chequeo.
* **Electricidad (`charge_array > 50`)**: `-2.5 HP` por chequeo (*Zeus es completamente inmune*).
* **Asfixia (Enterrado sin aire alrededor de la cabeza)**: `-3.0 HP` por chequeo (`-1.0 HP` si es controlado).

---

## 3. Fichas Detalladas por NPC

### 3.1 ⚔️ Guerrero (`"warrior"`)
* **Nombre en Juego**: `⚔️ Guerrero` / `⚔️ Warrior`
* **Nombre Técnico**: `"warrior"`
* **ID de Material**: `1000` (`1000–1008`)
* **Facción**: Equipos (`0`: Rojo, `1`: Azul, `2`: Amarillo, `3`: Verde)
* **Dimensiones**: `5 × 7` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Ataque**:
  * **Daño**: `15.0 × atk_dmg` (`12.0 – 18.75 HP`)
  * **Alcance**: `< 6 px` en X e Y
  * **Cooldown**: `0.6 s` (`0.4 s` al atacar al aire en Modo Arcade)
  * **Efecto Especial**: Avanza hasta `3 px` hacia la víctima al golpear y tiene `35%` de probabilidad de lanzar al enemigo por los aires (`vx = 3..5`, `vy = -4..-8`). Si posee `is_fire_variant` (`5%`), prende fuego al objetivo.
* **Perfil IA (`NPC_PROFILES`)**: Socializa ✅ | Duerme ✅ | Celebra ✅ | Huye con baja vida ✅ | Pánico en desastres ✅

---

### 3.2 🏹 Arquero (`"archer"`)
* **Nombre en Juego**: `🏹 Arquero` / `🏹 Archer`
* **Nombre Técnico**: `"archer"`
* **ID de Material**: `1010` (`1010–1015`, flecha `1012`)
* **Facción**: Equipos (`0..3`)
* **Dimensiones**: `5 × 7` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Ataque**:
  * **Tipo**: Proyectil balístico (`type = "arrow"`, gravedad `200.0`, vida útil `2.5 s`).
  * **Daño**: `40.0 × atk_dmg` (`32.0 – 50.0 HP`). Si `is_fire_variant` (`5%`), incendia al impactar.
  * **Alcance y Posicionamiento**: Se acerca si el enemigo está a `> 120 px` y retrocede (kiting) si el enemigo se acerca a `< 50 px`.
  * **Cooldown**: `1.1 s` (a distancia `> 50 px`) o `1.5 s` (a corta distancia `< 50 px`); `1.0 s` en Modo Arcade.
  * **Defensa Especial**: Cuando un atacante cuerpo a cuerpo lo golpea, el Arquero repele al atacante hacia atrás (`attacker.vx = -push_dir * 3.5`, `attacker.vy = -4.0`).
* **Perfil IA (`NPC_PROFILES`)**: Socializa ✅ | Duerme ✅ | Celebra ✅ | Huye con baja vida ✅ | Pánico en desastres ✅

---

### 3.3 ⛏️ Minero (`"miner"`)
* **Nombre en Juego**: `⛏️ Minero` / `⛏️ Miner`
* **Nombre Técnico**: `"miner"`
* **ID de Material**: `1020` (`1020–1024`)
* **Facción**: Equipos (`0..3`)
* **Dimensiones**: `5 × 8` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Habilidad y Ataque**:
  * **Excavación Autónoma**: Alterna entre estado `"ramp"` (`15–25` pasos excavando en diagonal hacia abajo) y `"gallery"` (`60–100` pasos horizontales), construyendo techos y pisos de madera (`ID 16`) y despejando túneles de `10 px` de alto.
  * **Modo Saboteador (`"saboteur"`)**: Al llegar al fondo del mapa (`dynamic_grid_height - 15`), coloca pisos de **TNT (`ID 5`)** y tras 3 rebotes detona el túnel con fuego (`ID 3`).
  * **Acción en Modo Arcade**: Coloca un bloque `2 × 2` de **TNT (`ID 5`)** frente a él (`cooldown = 1.5 s`) y excava automáticamente al caminar contra paredes o hacia abajo (`cada 0.14 s`).
* **Perfil IA (`NPC_PROFILES`)**: Socializa ✅ | Duerme ✅ | Celebra ✅ | Huye con baja vida ✅ | Pánico en desastres ✅

---

### 3.4 💊 Médico (`"medic"`)
* **Nombre en Juego**: `💊 Médico` / `💊 Medic`
* **Nombre Técnico**: `"medic"`
* **ID de Material**: `1040` (`1040–1045`)
* **Facción**: Equipos (`0..3`)
* **Dimensiones**: `5 × 7` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Habilidad de Soporte**:
  * **Curación IA**: Escanea aliados heridos en `180 px`, se acerca a menos de `25 px` y restaura `heal_power` (`15.0 – 35.0 HP`) cada `1.0 s`, restaurando además la moral rota (`is_fleeing = false`).
  * **Curación en Modo Arcade**: Cura en área a todos los aliados dentro de `60 px` (`cooldown = 0.8 s`).
  * **Evasión**: Huye automáticamente si hay un enemigo a `< 120 px` y no tiene aliados que curar (o tiene `< 50%` de vida).
* **Perfil IA (`NPC_PROFILES`)**: Socializa ✅ | Duerme ✅ | Celebra ✅ | Huye con baja vida ✅ | Pánico en desastres ✅

---

### 3.5 🧙 Mago (`"mage"`)
* **Nombre en Juego**: `🧙 Mago` / `🧙 Wizard`
* **Nombre Técnico**: `"mage"`
* **ID de Material**: `1070` (`1070–1077`)
* **Facción**: Equipos (`0..3`)
* **Dimensiones**: `8 × 10` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Ataque y Habilidades**:
  * **Bola de Fuego (`_shoot_fireball`)**: Proyectil parabólico (`gravity = 120.0`, vida `3.0 s`).
  * **Daño**: `35.0 × atk_dmg` (`28.0 – 43.75 HP`) + prende fuego (`ID 3`) al impactar.
  * **Conversión Mágica**: `5%` de probabilidad al impactar a un NPC enemigo de convertirlo permanentemente al equipo del Mago (`_convert_to_ally`).
  * **Alcance y Posicionamiento**: Mantiene distancia entre `35 px` y `110 px`.
  * **Cooldown**: `1.8 s` (`1.5 s` en Modo Arcade).
  * **Rescate Telequinético (`_process_mage_rescue`)**: Si un aliado se está asfixiando enterrado, corre al doble de velocidad (`step_size = 2`) y levanta mágicamente los bloques sobre su aliado (`magic_lifted`).
* **Perfil IA (`NPC_PROFILES`)**: Socializa ✅ | Duerme ✅ | Celebra ✅ | Huye con baja vida ✅ | Pánico en desastres ✅

---

### 3.6 🧟 Zombie (`"zombie"`)
* **Nombre en Juego**: `Zombie`
* **Nombre Técnico**: `"zombie"`
* **ID de Material**: `1050` (Master de renderizado `1080`)
* **Facción**: Sin bando (`team = -1`, aliado con otros Zombies, hostil a todos los demás)
* **Dimensiones**: `5 × 7` px
* **Vida Base**: `85 – 115 HP` (Promedio: `100 HP`)
* **Ataque e Infección**:
  * **Daño**: `15.0 × atk_dmg` (`12.0 – 18.75 HP`) cuerpo a cuerpo (`< 6 px`).
  * **Cooldown**: `0.8 s`.
  * **Infección (`zombie_infected`)**: Marca a las víctimas humanas; si bajan del `20%` de vida (`50%` prob.) o mueren por el golpe, se transforman en nuevos Zombies (`_convert_to_zombie`).
  * **Movimiento**: En patrulla solo avanza `1` de cada `3` ticks; salta ocasionalmente con `vy = -3.0 a -4.7`.
* **Perfil IA (`NPC_PROFILES`)**: Socializa ❌ | Duerme ❌ | Celebra ❌ | Huye ❌ | Pánico en desastres ❌

---

### 3.7 🧌 Zombie Tanque (`"zombie_tank"`)
* **Nombre en Juego**: `Zombie Tanque` / `Zombie Tank`
* **Nombre Técnico**: `"zombie_tank"`
* **ID de Material**: `1060` (Master de renderizado `1080`)
* **Facción**: Sin bando (`team = -1`, aliado con Zombies)
* **Dimensiones**: `6 × 9` px
* **Vida Base**: `280 – 320 HP` (Promedio: `300 HP`, `3×` Guerrero)
* **Ataques**:
  * **Cuerpo a Cuerpo**: `< 7 px`, daño `15.0 × atk_dmg` + infección zombie, `cooldown = 1.0 s`.
  * **Lanzamiento de Bloque (`thrown_rock`)**: Entre `35 px` y `150 px`, arranca un bloque real del terreno cercano y lo arroja en parábola (`cooldown = 2.5 s`, `2.0 s` en Modo Arcade). Al impactar destruye radio `3 px` e inflige hasta `75.0 HP` (`50.0 × 1.5`) de daño explosivo en un radio de `18 px`.
  * **Movimiento**: En patrulla solo se mueve `1` de cada `4` ticks.
* **Perfil IA (`NPC_PROFILES`)**: Socializa ❌ | Duerme ❌ | Celebra ❌ | Huye ❌ | Pánico en desastres ❌

---

### 3.8 🦖 Dinosaurio (`"dinosaurio"`)
* **Nombre en Juego**: `🦖 Dinosaurio` / `🦖 Dinosaur`
* **Nombre Técnico**: `"dinosaurio"`
* **ID de Material**: `1090` (Master de renderizado `1080`)
* **Facción**: Sin bando (`team = -1`, hostil contra **todos**, incluidos Zombies, Equipos, Zeus y otros Dinosaurios)
* **Dimensiones**: `15 × 11` px
* **Vida Base**: `500 – 600 HP` (Promedio: `550 HP`)
* **Ataque**:
  * **Mordisco Colosal**: Multiplica su `atk_dmg` por `4.0` al atacar (`60.0 × atk_dmg`, es decir `48.0 – 75.0 HP` por mordisco).
  * **Alcance**: `10.5 px + mitad del ancho del enemigo` desde su centro, altura `< 14 px`.
  * **Cooldown**: `0.6 s` (`1.0 s` en Modo Arcade).
  * **Inmunidades**: No puede ser infectado ni convertido en Zombie.
* **Perfil IA (`NPC_PROFILES`)**: Socializa ❌ | Duerme ✅ | Celebra ✅ | Huye ❌ | Pánico en desastres ❌

---

### 3.9 ⚡ Zeus (`"zeus"`)
* **Nombre en Juego**: `⚡ Zeus`
* **Nombre Técnico**: `"zeus"`
* **ID de Material**: `1100`
* **Facción**: Sin bando (`team = -1`, hostil contra **todos** los NPCs y facciones)
* **Dimensiones**: `7 × 10` px (`standing`: `7 × 10`, `lying`: `10 × 5`, `action`: `9 × 10`)
* **Vida Base**: `500.0 HP` (**exactamente `5×` la vida base de un Guerrero**)
* **Ataque y Habilidades**:
  * **Rayo Celestial (`_strike_lightning_at`)**: Invoca el elemento **Rayo** directamente desde el cielo sobre la coordenada X central de su objetivo, trazando una columna de electricidad (`ID 9`) que al impactar detona una explosión eléctrica de radio `5 px` (`EXP_VOLCANO | 128`, hasta `120.0 HP` de daño en el epicentro + empuje + chispas eléctricas `ID 43`).
  * **Alcance y Posicionamiento**: Camina normalmente hacia su objetivo si está a `> 95 px`, se detiene a distancia óptima (`25 – 95 px`), retrocede si el enemigo se acerca a `< 25 px`, y descarga rayos contra objetivos a `<= 140 px`.
  * **Cooldown**: `1.8 s` en IA autónoma (`1.5 s` en Modo Controlado Arcade).
  * **Inmunidades Divinas**:
    * **100% Inmune a daño por corriente eléctrica** (`charge_array > 50`).
    * **100% Inmune a explosiones eléctricas** (`ignition_flags & 128`), por lo que sus propios rayos jamás lo dañan ni empujan.
    * **Inmune a la infección Zombie** (no puede transformarse en Zombie por mordiscos ni por ácido).
* **Perfil IA (`NPC_PROFILES`)**: Socializa ❌ | Duerme ✅ | Celebra ✅ | Huye ❌ | Pánico en desastres ❌
