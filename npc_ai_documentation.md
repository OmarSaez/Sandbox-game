# Documentación de Inteligencia Artificial (NPCs)

Este documento mapea detalladamente cómo el juego toma decisiones para cada NPC basándose en su `npc.type`. Servirá como guía clave para que, al momento de reestructurar el motor visual y usar "Perfiles de IA", no rompamos ningún comportamiento.

## 1. El Bucle Principal (`_process_npcs`)
La lógica central de la IA se ejecuta cada fotograma. El código primero revisa los **comportamientos generales** y luego delega en bloques `if/elif` masivos para los **ataques y movimientos únicos** de cada clase.

---

## 2. Comportamientos Generales (Dependen de `NPC_PROFILES`)
El juego ya tiene un diccionario llamado `NPC_PROFILES` al inicio de `sandbox_grid.gd` que dicta quién puede hacer qué:

*   **Socializar (`can_socialize`):** Si no hay enemigos cerca, los NPCs buscan a un aliado cercano y entablan una conversación (aparecen emojis aleatorios de temas de charla).
*   **Aburrirse:** Si no han socializado ni peleado, tienen una pequeña probabilidad de bostezar (`🥱`).
*   **Dormir (`can_sleep`):** Si han pasado más de 120 segundos sin combates en el mapa (`_world_peace_timer > 120.0`), se acuestan en el suelo (`😴`).
*   **Colapsar:** Si la salud de un humano baja al 20%, pueden tirarse al suelo heridos (`🤕`).
*   **Huir (`can_flee`):** Si la salud baja al 30%, su "moral se rompe", empiezan a llorar (`😭`) y corren en dirección contraria al enemigo, dejando caer sudor/lágrimas de vez en cuando (material arena u otro dependiendo del código).
*   **Celebrar (`can_celebrate`):** Bailan y saltan cuando matan a un enemigo.

*Nota:* Los Zombies y Zombie Tanks tienen **todas estas opciones desactivadas** (en falso) en `NPC_PROFILES`.

---

## 3. Comportamientos Únicos por Tipo (`npc.type`)
Si un NPC detecta a un enemigo (o aliado que curar), el código entra en la lógica de combate específica:

### ⚔️ Guerrero (`warrior`)
*   **Movimiento:** Corre directamente hacia el enemigo más cercano. Si el enemigo está en una plataforma alta, intenta buscar un camino o se queda debajo esperando.
*   **Ataque:** Daño cuerpo a cuerpo constante si está a menos de 6 píxeles (`_attack_npc`). Cooldown: 0.6s.

### 🏹 Arquero (`archer`)
*   **Movimiento Estratégico:** Intenta mantenerse a una distancia media. Si el enemigo está muy lejos (>120 px) se acerca. Si el enemigo está muy cerca (<50 px) huye y toma distancia.
*   **Ataque:** Dispara flechas (`_shoot_arrow`). Tiene una mecánica de "fallar" (`miss_counter`); a veces decide moverse un poco en lugar de disparar para simular apuntar. Cooldown: 1.1s - 1.5s.

### 🧙‍♂️ Mago (`mage`)
*   **Movimiento Estratégico:** Similar al arquero, se mantiene a distancia (entre 35px y 110px).
*   **Ataque:** Dispara bolas de fuego (`_shoot_fireball`) con parábola gravitacional. Cooldown: 1.8s.
*   **Habilidad Especial (Rescate):** Tiene la función `_process_mage_rescue(npc)` separada, que escanea si algún aliado se está asfixiando bajo arena. De ser así, se acerca y usa magia para "levantar" los bloques, salvándolo.

### ⛏️ Minero (`miner`)
*   **Minería:** No tiene lógica de combate estándar. En cada ciclo aumenta un `dig_timer` y destruye los bloques que tiene en frente. 
*   **Saboteador:** Puede entrar en estado `mine_state == "saboteur"` para destruir estructuras enemigas o romper el mapa de formas específicas.

### 💚 Curandero (`medic`)
*   **Huir:** Nunca ataca a los enemigos. Siempre se aleja de ellos.
*   **Curar:** Su `target` principal no son los enemigos, sino aliados con daño. Se acerca a ellos y ejecuta curación en área.

### 🧟 Zombie normal (`zombie`)
*   **Movimiento Torpe:** Solo se mueve 1 de cada 3 fotogramas. Camina lento hacia el enemigo. Suelta emojis de cerebro (`🧠`) y carne (`🥩`).
*   **Ataque:** Cuerpo a cuerpo si está a menos de 6 píxeles. Esparce infección si mata a un humano.

### 🧌 Zombie Tanque (`zombie_tank`)
*   **Movimiento Muy Torpe:** Solo se mueve 1 de cada 4 fotogramas.
*   **Ataque Corto Rango:** Cuerpo a cuerpo pesado.
*   **Ataque Largo Rango (Lanzar Rocas):** Si el enemigo está entre 35px y 150px, escanea el terreno debajo y detrás de él, **arranca un pedazo de material sólido real del mapa**, y lo lanza como un proyectil letal hacia el enemigo (`_launch_flying_block`). Cooldown: 2.5s.

---

## 4. Conclusión para la Refactorización

Tu código de IA está muy bien estructurado en bloques `if/elif`. Gracias a que existe el `NPC_PROFILES` en la línea 829, ya tenemos la mitad del trabajo de Data-Driven hecho.

Al crear la herramienta de diseño de NPCs visual, el único cambio que haremos será este:
* En lugar de que el código verifique la cadena literal `"warrior"`, verificaremos el "Cerebro" asignado.
* Si el jugador dibuja un "Gólem de Hielo" y le asigna el cerebro de `zombie_tank`, el motor leerá este documento y sabrá que debe correr el bloque de lanzar bloques pesados y moverse lento.
