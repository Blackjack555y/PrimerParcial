# Diseno del agente Ruby para Emergency Control

**Estado:** implementado y validado en `parcial/` (Ruby). Las secciones 4.3, 7.1, 13 y 15 se actualizaron despues de la implementacion para reflejar decisiones que la medicion empirica corrigio respecto del diseno original; el resto del documento describe el diseno tal como se implemento. Ver `parcial/CONTINUACION.md` para el historial de trabajo.

Este documento define el agente que se implementara posteriormente en Ruby para la instancia descrita en [Analisis.md](../Analisis.md). No contiene codigo ejecutable. Su objetivo es fijar con claridad la representacion del problema, las reglas del mundo, las acciones, la funcion de costo y la estrategia de busqueda antes de escribir el solver.

## 1. Alcance y supuestos

El agente recibe un escenario JSON y debe devolver un plan que cumpla el contrato de la asignatura. El escenario es:

- Totalmente observable: el agente conoce zonas, objetos, puertas, paneles y estaciones.
- Determinista: una accion legal tiene un unico resultado.
- Secuencial: cada accion modifica el estado para la siguiente decision.
- Estatico durante la planificacion: no aparecen eventos externos.
- Discreto: las posiciones y acciones pertenecen a un conjunto finito.
- De agente unico: solo el robot toma decisiones.

Por estas propiedades, el problema se formula como busqueda clasica en un grafo de estados. Como los costos son positivos y no uniformes, la estrategia elegida es **Uniform Cost Search (UCS)**.

El diseno contempla dos fronteras:

1. **Modelo del mundo:** decide si una accion es legal y calcula su resultado.
2. **Agente de busqueda:** genera sucesores relevantes, acumula costos y encuentra un plan optimo.

La vista HTML del grafo (la que esta en frontend/grafo) es solamente una representacion visual. No decide legalidad, no modifica estados y no reemplaza el escenario JSON.

## 2. Objetivo del agente

El agente debe encontrar un plan de costo minimo que deje online las tres estaciones de la instancia:

```text
goal.stations_online = { GENERATOR, COMMAND, ARTILLERY }
```

No es necesario que el robot termine en una zona concreta. Tampoco se exige una bateria final minima ni que la carga quede vacia. Las puertas abiertas, los paneles reparados y los objetos abandonados son medios para alcanzar la meta, no condiciones adicionales de la meta.

El agente trabaja con acciones internas expresivas, pero la salida final solo puede usar las cuatro operaciones visuales del contrato:

- `MOVE`
- `PICKUP`
- `DROP`
- `INTERACT`

Las interacciones se traducen a `OPEN_DOOR`, `REPAIR`, `ACTIVATE` o `RECHARGE` segun corresponda.

## 3. Representacion formal del estado

El estado fisico se define como:

```text
s = <pos, battery, carried, floor, doors_open, panels_repaired, stations_online>
```

Donde:

| Componente | Significado |
|---|---|
| `pos` | Zona actual del robot, por ejemplo `Z3` |
| `battery` | Bateria residual del robot |
| `carried` | Objetos que el robot lleva, en forma canonica |
| `floor` | Objetos disponibles en cada zona, en forma canonica |
| `doors_open` | Conjunto de puertas abiertas |
| `panels_repaired` | Conjunto de paneles reparados |
| `stations_online` | Conjunto de estaciones activadas |

`g(n)`, la accion anterior y el padre del nodo no pertenecen al estado fisico. Esos datos pertenecen al nodo de busqueda porque describen el camino recorrido, no la configuracion actual del mundo.

### 3.1 Por que cada componente es necesario

- **`pos`:** determina que corredores, objetos, paneles, estaciones y cargadores puede alcanzar o usar inmediatamente.
- **`battery`:** una accion puede ser legal o ilegal dependiendo de la energia disponible. En esta instancia la bateria inicial 55 y el cargador unico en `Z3` son restricciones activas.
- **`carried`:** determina que llaves, herramientas y materiales puede usar el robot y cuanto espacio queda.
- **`floor`:** `DROP` permite cambiar la ubicacion de un objeto. La posicion actual de un objeto no se puede deducir siempre del escenario inicial.
- **`doors_open`:** una puerta abierta permite movimientos futuros que antes estaban bloqueados. Las puertas permanecen abiertas.
- **`panels_repaired`:** una reparacion habilita estaciones y no puede deshacerse.
- **`stations_online`:** representa el progreso de la meta y las dependencias de activacion.

Si dos configuraciones difieren en cualquiera de estas variables, pueden tener acciones futuras distintas o producir resultados distintos; por eso son parte del estado.

### 3.2 Informacion derivada

No se almacena como variable independiente aquello que puede calcularse a partir del estado y de las constantes del escenario:

- Peso total de la carga.
- Capacidad restante.
- Vecinos de una zona.
- Costo de cada movimiento.
- Si una zona tiene cargador.
- Herramienta o material requerido por un panel.
- Si una accion supera la bateria disponible.
- Si una estacion cumple sus paneles y dependencias.

Guardar estos datos duplicados podria producir estados incoherentes. Ruby los calculara mediante funciones del modelo del escenario.

### 3.3 Estado inicial y ubicacion de objetos

El estado inicial se construye exclusivamente a partir del escenario recibido:

```text
pos = robot.start
battery = robot.battery_start
carried = vacio
floor = ubicaciones iniciales de keys, tools y materials
doors_open = puertas cuyo estado inicial es OPEN
panels_repaired = paneles cuyo estado inicial es REPAIRED
stations_online = estaciones cuyo estado inicial es ONLINE
```

El algoritmo no debe asumir que el robot siempre empieza sin objetos ni que
todas las puertas, paneles y estaciones empiezan cerrados, danados u offline.
Esas condiciones se leen del JSON. Los objetos soltados se agregan a
`floor[pos]` y nunca se crean ids nuevos para materiales fungibles.

## 4. Representacion canonica en Ruby

La implementacion usara objetos de valor inmutables o estructuras equivalentes. Un estado canonico debe ser comparable por valor y debe producir siempre el mismo `hash` para la misma situacion fisica.

### 4.1 Colecciones ordenadas

- `doors_open`, `panels_repaired` y `stations_online` se representan como conjuntos ordenados de identificadores.
- La carga de llaves y herramientas se representa como conjunto ordenado de ids.
- La carga de materiales se representa como contador por tipo, por ejemplo `{ FUSE: 1, CHIP: 1 }`.
- Los materiales que estan en el suelo se representan como contadores por zona y tipo, no como ids artificiales.
- Las posiciones de objetos relevantes en el suelo se almacenan agrupadas por zona y por tipo o id.

El orden canonico evita que estas dos representaciones creen estados distintos:

```text
[KEY1, MULTITOOL, CHIP]
[MULTITOOL, CHIP, KEY1]
```

### 4.2 Materiales fungibles

Los dos `FUSE` son indistinguibles para el futuro. El estado debe guardar cantidades, no inventar `FUSE_1` y `FUSE_2`.

Por ejemplo, estas situaciones son equivalentes cuando el resto del estado coincide:

```text
carried_materials = { FUSE: 1 }
```

No importa cual unidad fisica de las dos fue recogida. Esta equivalencia es necesaria para que `CLOSED` fusione historias distintas y el espacio no crezca artificialmente.

### 4.3 Objetos muertos

El mundo tiene cambios monotonos: una puerta abierta no se cierra, un panel reparado no vuelve a estar danado y una estacion activada no se apaga.

La representacion puede conservar un objeto en el estado mientras todavia tenga un efecto futuro. Cuando deja de tenerlo, puede eliminarse de la parte relevante del estado mediante una regla de abstraccion:

- Una llave deja de ser relevante cuando su puerta ya esta abierta.
- Un material deja de ser relevante cuando el panel que lo consume ya fue reparado.
- Una herramienta deja de ser relevante para la busqueda cuando todos los paneles que puede reparar ya estan reparados.

La eliminacion es valida solo si el objeto ya no puede habilitar una accion futura ni cambiar el costo de una accion futura. No se elimina por conveniencia antes de comprobar esa condicion.

**Actualizacion post-implementacion:** esta poda se implemento como `State#canonical_key(liveness)`, que recibe un `ItemLiveness` construido por `UcsSolver` a partir del escenario. `State` sigue sin conocer el escenario: solo le pregunta a `liveness` si un objeto del `floor` sigue vivo. El `floor` fisico nunca se muta -- `canonical_key` solo se usa para la clave de dominancia/`CLOSED`, de forma que dos estados que difieren unicamente en la posicion de un objeto muerto colapsan a la misma clave sin perder informacion fisica que otra parte del modelo pudiera necesitar. Cubierto por pruebas de equivalencia en `parcial/test/test_search_properties.rb` (caso 1). El impacto medido de esta poda por si sola fue menor al esperado (~1.5% de reduccion de estados unicos en el diagnostico acotado); la causa dominante de la explosion de estados resulto ser la generacion de `DROP` (ver 7.1).

## 5. Modelo del escenario

El escenario JSON es la fuente de verdad. El modelo de Ruby lo cargara sin cambiar sus valores:

- `robot.start = Z1`.
- `battery_start = 55` y `battery_max = 100`.
- `cargo_capacity = 3`.
- `Z3` es el unico punto de recarga.
- Los corredores y sus costos se leen de `corridors`.
- Las puertas se relacionan con corredores mediante su id.
- Las llaves, herramientas y materiales conservan su zona inicial.
- Los paneles y estaciones conservan sus requisitos.

El modelo debe soportar escenarios con la misma forma, no depender de que los ids de esta demo aparezcan escritos dentro del algoritmo.

## 6. Acciones internas

Toda accion tiene una precondicion de bateria: la bateria residual debe ser al menos igual al costo de la accion. `MOVE` consume energia igual al costo del corredor; las demas acciones consumen su costo oficial.

| Accion interna | Precondiciones principales | Efectos | Costo |
|---|---|---|---:|
| `MOVE(to)` | Existe corredor desde `pos`; puerta ausente o abierta; bateria suficiente | Cambia `pos` a `to`; resta costo del corredor | Costo del corredor |
| `PICKUP(item)` | El objeto esta en el suelo de `pos`; hay capacidad; el objeto sigue disponible | Pasa el objeto del suelo a `carried` | 1 |
| `DROP(item)` | El objeto esta en `carried` y la ubicacion es estrategicamente necesaria | Pasa el objeto a `floor[pos]` | 1 |
| `OPEN_DOOR(door)` | El robot esta junto al corredor de la puerta; la puerta esta cerrada; lleva la llave correcta | Agrega la puerta a `doors_open`; la llave deja de ser necesaria | 2 |
| `REPAIR(panel)` | El robot esta en la zona del panel; lleva herramienta y material requeridos; panel danado | Agrega el panel a `panels_repaired`; consume el material; conserva la herramienta | 2 |
| `ACTIVATE(station)` | El robot esta en la zona; paneles requeridos reparados; estaciones previas online | Agrega la estacion a `stations_online` | 2 |
| `RECHARGE(charger)` | El robot esta en la zona del cargador; bateria menor que `battery_max`; bateria suficiente para pagar | Restaura `battery` a `battery_max` | `action_costs.recharge` |

`OPEN_DOOR` y `RECHARGE` son acciones internas. La traduccion de salida las expresa mediante `INTERACT` con el `action` exigido por el contrato.

### 6.1 Reglas de movimiento

El movimiento es dirigido. Para la instancia actual los costos son simetricos, pero el algoritmo no debe asumir simetria:

- `Z1 <-> Z2`: costo 4, `DOOR1`.
- `Z2 <-> Z3`: costo 6, `DOOR2`.
- `Z3 <-> Z4`: costo 5, sin puerta.
- `Z4 <-> Z5`: costo 3, `DOOR3`.
- `Z1 <-> Z4`: costo 8, sin puerta.
- `Z2 <-> Z5`: costo 12, sin puerta.

La accion `MOVE` nunca abre una puerta implicitamente. Primero debe ejecutarse `OPEN_DOOR` con la llave correspondiente.

### 6.2 Reglas de reparacion y activacion

- `PANEL_A` requiere `MULTITOOL` y un `FUSE` en `Z4`.
- `PANEL_B` requiere `SOLDERING` y un `CHIP` en `Z5`.
- `PANEL_C` requiere `WIRE_CUTTER` y un `CABLE` en `Z5`.
- `GENERATOR` requiere `PANEL_A` reparado.
- `COMMAND` requiere `PANEL_B` reparado y `GENERATOR` online.
- `ARTILLERY` requiere `PANEL_C` reparado y `GENERATOR` online.

`COMMAND` y `ARTILLERY` pueden activarse en cualquier orden despues de `GENERATOR`.

## 7. `Applicable(s)` y control de `PICKUP`/`DROP`

`Applicable(s)` es el conjunto de acciones que el agente decide explorar desde
un estado. No tiene que ser identico al conjunto de operaciones que el
simulador aceptaria. El simulador define legalidad; el generador define que
acciones legales son relevantes para buscar un plan optimo.

### 7.1 `PICKUP` util

Un objeto es util si aun puede contribuir a la meta:

- Una llave, si la puerta que abre sigue cerrada.
- Una herramienta, si todavia existe un panel pendiente que puede reparar.
- Un material, si existe un panel pendiente que lo consume.

No se genera `PICKUP` de un objeto que ya cumplio su funcion. Recogerlo
consume costo, bateria y capacidad, pero no habilita ninguna accion futura;
por tanto ningun plan optimo necesita hacerlo. En un escenario general, una
herramienta o material se conserva mientras exista al menos un uso pendiente.

La precondicion comun de `PICKUP` es:

```text
objeto pertenece a floor[pos]
payload_weight + weight(objeto) <= cargo_capacity
battery >= action_costs.pickup
```

El efecto mueve el objeto del suelo a la carga y descuenta el costo oficial.

El contrato del mundo permite soltar un objeto en cualquier zona donde este el robot. Sin embargo, generar todos esos `DROP` convierte cada ubicacion posible de cada objeto en una rama innecesaria.

El generador de sucesores debe producir acciones legales y relevantes para un plan optimo. En particular, no generara todos los `DROP` posibles. Generara `DROP` solo en estos casos:

1. **Liberar capacidad:** la carga esta llena y se necesita recoger un objeto util que esta en la zona actual.
2. **Preparar una transferencia local:** dejar un objeto en la zona actual permite recoger otro objeto necesario sin perder el primero.
3. **Descartar un objeto muerto:** despues de abrir una puerta o reparar el ultimo panel para el que sirve, soltar una llave o herramienta puede liberar capacidad.

La accion no debe ofrecer destinos arbitrarios: el unico destino generado es `floor[pos]`, la zona donde el robot se encuentra. Dejar un objeto y volver a recogerlo sin que cambie ninguna precondicion nunca reduce costo, porque agrega al menos 2 unidades de accion (`DROP` + `PICKUP`) y no mejora la posicion del robot.

En esta instancia, la capacidad 3 frente a los cuatro objetos necesarios para `PANEL_B` y `PANEL_C` hace que un `DROP` de un objeto todavia util pareciera potencialmente obligatorio. La poda conserva ese caso y elimina los `DROP` que solo permutan objetos sin impacto futuro.

**Actualizacion post-implementacion:** esta prediccion no se sostuvo empiricamente. `Applicable(s)` se implemento primero permitiendo `DROP` de un objeto vivo cuando no es necesario en la zona actual (poda `needed_here`), y por separado con una poda mas estricta que nunca ofrece `DROP` de un objeto vivo, sin importar la zona (poda `dead_only`, portada de una referencia en Python). Medido sobre la instancia real con el mismo limite de expansiones: `needed_here` no converge (no encuentra la meta ni con 200.000 expansiones); `dead_only` converge en 35.786 expansiones y encuentra el plan de costo optimo (88), porque existe una reordenacion de la ruta -- separar el viaje por herramientas del viaje por materiales -- que evita retener simultaneamente los 4 objetos sin necesitar soltar ninguno vivo. `Applicable(s)` restringe entonces `DROP` a objetos muertos unicamente; la poda `needed_here` se conserva en el codigo (`SuccessorGenerator#drop_actions`, parametro `drop_policy:`) por si una instancia futura si lo exigiera, pero no es la politica por defecto. En otras palabras: para esta instancia, la restriccion de capacidad se resuelve con planificacion de ruta, no con sacrificar carga util.

**No es una prueba de completitud.** No se encontro (tras intentarlo con varias construcciones) un escenario razonable donde `dead_only` falle genuinamente teniendo `needed_here` una solucion -- la monotonia del mundo (puertas, paneles y estaciones nunca revierten) parece permitir resolver casi cualquier restriccion de capacidad recogiendo un par herramienta+material a la vez y regresando por el siguiente. Pero eso es evidencia empirica repetida, no una demostracion formal de que `dead_only` sea completo para toda instancia con esta forma. Por eso `UcsSolver#solve` no confia unicamente en `dead_only`: si la busqueda con `dead_only` agota su espacio de estados sin encontrar meta (la frontera se vacia, no un limite de expansiones truncando la corrida), reintenta una sola vez con `needed_here` antes de declarar `FAILURE`. El costo de este resguardo es cero cuando `dead_only` ya encuentra plan (el caso medido aqui), y solo se paga en la instancia rara donde realmente hace falta.

### 7.2 Acciones que no se generan

- `PICKUP` de un material excedente cuando no existe panel pendiente que pueda consumirlo.
- `OPEN_DOOR` para una puerta ya abierta.
- `REPAIR` de un panel ya reparado.
- `ACTIVATE` de una estacion ya online.
- `RECHARGE` cuando la bateria ya esta al maximo.
- `MOVE` a traves de una puerta cerrada.
- `DROP` de un objeto que no libera capacidad ni prepara una accion necesaria.

Estas restricciones reducen el factor de ramificacion sin cambiar el conjunto de planes optimos relevantes.

## 8. Modelo de transicion

La transicion es determinista y parcial:

```text
s --a--> s'  si y solo si a pertenece a Applicable(s)
```

`Result(s, a)` realiza una copia inmutable del estado y aplica exactamente los efectos de la accion. Nunca modifica el estado que ya esta en `CLOSED`.

### 8.1 Cambios permitidos

- `MOVE` cambia `pos` y disminuye `battery`.
- `PICKUP` y `DROP` mueven objetos entre `floor` y `carried`, y actualizan capacidad derivada.
- `OPEN_DOOR` cambia `doors_open`.
- `REPAIR` cambia `panels_repaired` y consume el material requerido.
- `ACTIVATE` cambia `stations_online`.
- `RECHARGE` cambia `battery` a `battery_max`.

### 8.2 Propiedades invariantes

La transicion debe conservar estas propiedades:

- La bateria nunca queda negativa ni supera `battery_max`.
- La carga nunca supera `cargo_capacity`.
- Un objeto no aparece simultaneamente en `carried` y en `floor`.
- Una puerta, panel o estacion solo avanza en sentido monotono.
- Un material consumido desaparece de la carga.
- Una herramienta reutilizable no desaparece al reparar.
- Ninguna accion cambia los costos definidos por el escenario.

Despues de cada transicion se reconstruyen las colecciones canonicas antes de calcular igualdad o hash.

## 9. Prueba de meta

La prueba de meta es:

```text
Goal(s) <=> goal.stations_online subset_of stations_online
```

En la demo esto equivale a comprobar que `GENERATOR`, `COMMAND` y `ARTILLERY`
esten online. En escenarios generales se compara con `goal.stations_online`,
no con una lista fija ni con igualdad estricta: podria haber estaciones
adicionales que no formen parte de la meta. Los paneles reparados y las
puertas abiertas son condiciones intermedias que hacen posible la meta, pero
no son suficientes por si mismas.

UCS comprueba la meta cuando extrae el nodo de menor costo de `OPEN`, no cuando lo genera. Asi, el primer nodo aceptado como meta es el de menor costo global.

## 10. Funcion de costo

El costo de un nodo es la suma de los costos oficiales de todas las acciones de su camino:

```text
g(n) = sum(cost(a_i)) para i = 1..k
```

Los costos concretos son:

- `PICKUP`: 1.
- `DROP`: 1.
- `OPEN_DOOR`, `REPAIR`, `ACTIVATE`: 2.
- `RECHARGE`: 3.
- `MOVE`: costo del corredor utilizado.

Minimizar el numero de acciones no es equivalente a minimizar `g(n)`: `Z1-Z4` cuesta 8, `Z2-Z5` cuesta 12 y los demas corredores tienen otros costos. Un plan con menos operaciones puede ser mas caro que otro con mas operaciones y corredores mas economicos.

## 11. Estrategia de busqueda: Uniform Cost Search

### 11.1 Eleccion

Se usara UCS porque:

- Los costos son no negativos y, en esta instancia, estrictamente positivos.
- El objetivo es minimizar el costo total, no la cantidad de pasos.
- El espacio de estados es finito si el escenario, la bateria y los objetos estan acotados.
- Las transiciones son deterministas.

La frontera `OPEN` se ordena por `g(n)` creciente. Cada entrada conserva el estado, el costo, el padre y la accion que produjo el estado.

### 11.2 Procedimiento conceptual

1. Construir el estado inicial desde el JSON.
2. Insertarlo en `OPEN` con costo cero.
3. Extraer el nodo de menor costo.
4. Descartarlo si es una entrada obsoleta o si ya existe una mejor etiqueta para el mismo estado.
5. Comprobar `Goal` al extraerlo.
6. Si no es meta, marcar su configuracion canonica y generar `Applicable(state)`.
7. Aplicar `Result` a cada accion relevante.
8. Insertar sucesores solo cuando mejoren el costo conocido.
9. Repetir hasta encontrar meta o vaciar `OPEN`.

La implementacion Ruby puede usar una cola de prioridad propia o una gema, pero la interfaz conceptual debe mantener estas garantias y permitir reconstruir el plan.

### 11.3 CLOSED y equivalencia

`CLOSED` no se basara en la identidad de objetos Ruby. Usara una clave canonica derivada de:

```text
[pos, battery, carried, floor, doors_open, panels_repaired, stations_online]
```

Las colecciones se ordenan y los materiales se cuentan antes de serializar la clave. Dos historias que produzcan la misma situacion fisica deben producir la misma clave.

Cuando una nueva ruta alcanza exactamente el mismo estado con un costo menor, se actualiza la mejor etiqueta y se permite una nueva expansion. Una entrada antigua que llegue despues se descarta.

### 11.4 Comprobacion de optimalidad

Con costos positivos, UCS es completo en este espacio finito y optimo: cuando un nodo meta sale de `OPEN`, no queda en la frontera otro camino de menor costo que pueda producir una solucion mas barata.

La prueba de meta al generar seria incorrecta para esta garantia, porque un nodo generado podria no ser el proximo nodo de menor costo.

### 11.5 Bateria y dominancia

La bateria forma parte del estado porque cambia la legalidad de acciones. Sin embargo, se puede aplicar una poda de dominancia con cuidado.

Para una misma configuracion fisica sin contar la bateria:

```text
(pos, carried, floor, doors_open, panels_repaired, stations_online)
```

una etiqueta `A` domina a `B` si:

```text
A.g <= B.g
A.battery >= B.battery
```

y al menos una desigualdad es estricta. Todo plan futuro posible desde `B` tambien es posible desde `A`, con costo no mayor y bateria suficiente. Por tanto, `B` no necesita conservarse.

No se debe reducir el estado a una sola bateria arbitraria. Si una ruta tiene menor costo pero menos bateria, puede no dominar una ruta mas cara que llega con energia suficiente. La tabla de mejores etiquetas debe considerar el par costo-bateria o, equivalentemente, mantener una frontera de etiquetas no dominadas por configuracion fisica.

## 12. Completitud, optimalidad y limites

### Completitud

UCS encuentra una solucion si existe, siempre que:

- El escenario sea finito.
- Las acciones tengan costos positivos o, como minimo, no negativos sin ciclos de costo cero problematicos.
- `Applicable` no elimine una accion necesaria de todos los planes optimos.
- La canonicalizacion no fusione estados que tengan futuros diferentes.

Si `OPEN` se vacia, el agente devuelve `solution_found = false`.

### Optimalidad

La optimalidad depende de tres decisiones:

1. Priorizar la frontera por costo acumulado.
2. Comprobar la meta al extraer el minimo.
3. Aplicar solo podas sound: nunca eliminar un plan optimo posible.

### Complejidad

El mapa tiene pocas zonas, pero el factor de ramificacion real depende de:

- Cantidad de `PICKUP` disponibles.
- Cantidad de objetos en la carga.
- Cantidad de `DROP` permitidos.
- Rutas alternativas.
- Niveles de bateria y recargas.
- Combinaciones de puertas, paneles y estaciones.

Un UCS ingenuo puede crear millones de nodos porque cada `DROP` arbitrario codifica una posicion distinta para cada objeto. La restriccion de `DROP`, los contadores de materiales, los conjuntos canonicos y la dominancia de bateria controlan esa explosion.

No se resolvera el problema alterando el escenario: no se subira artificialmente la capacidad, no se eliminaran estaciones, no se ignorara la bateria y no se cambiaran costos.

### Formulacion y tamano del espacio (obligatorio)

**1. Por que "5 zonas, ~10 objetos, capacidad 3" puede generar millones de nodos en un UCS ingenuo.**
Si `Applicable(s)` generara `DROP` sin restriccion, la posicion de cada objeto deja de estar fija y pasa a ser una variable independiente: cada uno de los ~10 objetos (3 llaves, 3 herramientas, 3 tipos de material) puede estar en cualquiera de las 5 zonas o en `carried`, es decir, del orden de `6^10 ≈ 6*10^7` combinaciones solo de `floor`. Multiplicado por `pos` (5), `doors_open` (`2^3`), `panels_repaired` (`2^3`), `stations_online` (acotado por dependencias pero hasta `2^3`) y los niveles de bateria alcanzables (hasta `battery_max = 100`, antes de aplicar la dominancia de 11.5), el espacio nominal supera ampliamente lo que UCS puede explorar en tiempo de examen. El mapa (5 zonas) no es lo que explota; la combinatoria de "donde quedo cada objeto" si.

**2. Que papel tiene `DROP` en esa explosion.**
Es la unica accion que puede colocar un objeto en una zona donde no empezo. Sin ninguna restriccion, cualquier estado con carga llena ofrece un `DROP` por cada objeto cargado, y cada uno de esos `DROP` es un estado fisico nuevo y no dominado (difiere en que quedo en el piso vs. en la carga). Esto se confirmo empiricamente durante la implementacion: instrumentando el `UcsSolver` real sobre `scenario.json`, antes de restringir `DROP` a objetos muertos, entre el 90% y el 100% de las acciones `DROP` generadas en la exploracion correspondian a objetos todavia utiles ofrecidos como candidatos especulativos de sacrificio, no a objetos ya inservibles (ver `parcial/CONTINUACION.md`).

**3. Que podas o abstracciones se aplicaron y por que son sound (no pierden el optimo).**

- **No generar `PICKUP` de un objeto muerto ni de material excedente** (7.1, `pickup_needed?`/`useful_item?`). Argumento: por definicion, un objeto muerto no puede habilitar ninguna accion futura ni abaratarla (una llave cuya puerta ya esta abierta nunca vuelve a usarse para abrir esa puerta; un material cuyo unico panel consumidor ya fue reparado nunca vuelve a ser requerido). Sea `π` un plan optimo que contiene `PICKUP(x)` con `x` muerto en ese punto. Como `x` nunca vuelve a ser referenciado por ninguna precondicion, `π' = π` sin ese `PICKUP` (y sin cualquier `DROP(x)` posterior) sigue siendo legal y `cost(π') <= cost(π)`. Por lo tanto `π` no puede ser estrictamente mejor que `π'`; la poda nunca descarta el unico plan optimo.
- **Canonicalizar el estado ignorando la posicion de objetos muertos en `floor`** (4.3, `State#canonical_key`). Argumento: `pickup_actions` y `drop_actions` ya filtran por `useful_item?`, de modo que la posicion exacta de un objeto muerto no aparece en ninguna precondicion evaluada por `Applicable(s)` ni por `Result`. Dos estados que solo difieren en donde quedo un objeto muerto producen exactamente el mismo conjunto de sucesores y los mismos costos; fusionarlos en `CLOSED` no descarta ningun futuro distinto porque no existe tal futuro distinto.
- **Dominancia de bateria por configuracion fisica** (11.5). Argumento ya desarrollado alli: si `A.g <= B.g` y `A.battery >= B.battery` para la misma configuracion fisica, todo plan futuro posible desde `B` es posible desde `A` con costo no mayor; `B` es redundante.
- **Restriccion de `DROP` a objetos muertos (`dead_only`, actualizacion de 7.1).** A diferencia de las tres anteriores, esta poda **no tiene una prueba de solidez general**: se justifica empiricamente (encuentra el plan de costo optimo medido, 88, en la instancia real) y se protege con el reintento automatico descrito en 7.1 para el caso en que una instancia distinta si dependa de soltar un objeto vivo. Es la unica poda de esta lista que se declara honesta y explicitamente como heuristica validada por medicion, no como teorema.

**4. Por que no es solucion subir la capacidad, bajar las estaciones o ignorar la bateria.**
Esos cambios ocultan el sintoma en la instancia de ejemplo sin resolver el problema de formulacion: el profesor probara instancias distintas (otras posiciones, costos, recursos, y posiblemente sin solucion), y un agente que solo funciona porque se le aflojaron las restricciones del mundo fallara en cuanto esas restricciones vuelvan a ser realistas. El arreglo correcto vive en `Applicable(s)` y en la canonicalizacion del estado, no en el escenario.

## 13. Arquitectura conceptual Ruby

La separacion propuesta para la implementacion es:

| Componente | Responsabilidad |
|---|---|
| `Scenario` | Leer y validar el JSON; exponer constantes del mundo |
| `State` | Representar un estado inmutable, canonico, comparable y hasheable |
| `Action` | Describir una accion interna y sus parametros |
| `TransitionModel` | Evaluar precondiciones y producir sucesores deterministas |
| `SuccessorGenerator` | Implementar `Applicable` y las podas sound |
| `PriorityQueue` | Mantener `OPEN` ordenada por costo |
| `UcsSolver` | Ejecutar UCS, `CLOSED`, dominancia y reconstruccion |
| `PlanFormatter` | Traducir acciones internas al contrato visual |

La interfaz HTTP o la pagina visual no deben contener reglas de busqueda. El backend recibe el escenario, llama al solver y devuelve el plan. El frontend solo visualiza el escenario y, posteriormente, la ejecucion del plan.

**Actualizacion post-implementacion:** `PlanValidator` no se construyo como clase separada. La correspondencia `total_cost == suma(steps.cost)` se verifica como aserciones en `parcial/test/test_solver_scenario.rb`, y la legalidad de cada paso la revalida el propio simulador del frontend de evaluacion, que segun `CONTRATO.md` "no confia en el plan". Duplicar esa validacion en el backend hubiera sido logica redundante sin un consumidor propio; se prefirio cubrirla con tests.

El servidor HTTP se implemento en `parcial/server.rb` usando unicamente `TCPServer` de la libreria estandar (sin gems): `gem install` fallo en la maquina de desarrollo por interceptacion SSL de un antivirus, lo que reafirma la decision de no depender de instalar nada para correr el backend.

## 14. Salida y contrato

La salida debe conservar el formato:

```json
{
  "solution_found": true,
  "total_cost": 63,
  "steps": [
    { "op": "MOVE", "from": "Z1", "to": "Z2", "cost": 4 },
    { "op": "PICKUP", "item": "KEY1", "cost": 1 },
    { "op": "INTERACT", "target": "DOOR1", "action": "OPEN_DOOR", "cost": 2 },
    { "op": "INTERACT", "target": "PANEL_A", "action": "REPAIR", "consumes": "FUSE", "cost": 2 },
    { "op": "INTERACT", "target": "CHARGER_1", "action": "RECHARGE", "cost": 3 }
  ],
  "message": "optional text"
}
```

Reglas de salida:

- Solo se usan `MOVE`, `PICKUP`, `DROP` e `INTERACT`.
- Cada movimiento debe existir en `corridors` y respetar puertas abiertas.
- Cada `PICKUP` y `DROP` debe ser legal en la simulacion.
- Cada `INTERACT` debe usar una accion permitida; `REPAIR` incluye `consumes`
  con el tipo de material correcto y `RECHARGE` referencia el cargador de la
  zona actual.
- `total_cost` debe ser exactamente la suma de los costos de `steps`.
- Si no existe solucion, se devuelve `solution_found: false` y `steps: []`.

## 15. Validacion prevista antes de implementar la interfaz

El diseño se considerara listo para implementacion cuando las pruebas conceptuales puedan expresarse como estas verificaciones:

1. **Equivalencia de estado:** dos historias que terminan con la misma configuracion canonica producen estados iguales y el mismo hash.
2. **Informacion relevante:** cambiar bateria, posicion, carga, puerta, panel o estacion puede cambiar las acciones futuras.
3. **Costo:** una ruta con menos acciones no se acepta automaticamente si tiene mayor costo.
4. **Sin solucion:** un escenario sin material, llave o corredor suficiente termina sin ciclo infinito.
5. **Rutas alternativas:** UCS elige el plan de menor costo entre rutas posibles hacia el mismo objetivo.
6. **Capacidad:** el solver resuelve la carga 3 frente a los cuatro objetos de `Z5`; en la implementacion final lo logra mediante reordenacion de ruta (viajes separados por herramienta y por material), no mediante `DROP` de un objeto vivo -- ver actualizacion en 7.1.
7. **Bateria:** el solver no permite movimientos con energia insuficiente y puede usar `RECHARGE` en `Z3`.
8. **Dependencias:** `COMMAND` y `ARTILLERY` no se activan antes de `GENERATOR`.

Las ocho verificaciones estan implementadas como pruebas automatizadas en `parcial/test/test_search_properties.rb` (casos 1 a 5) y `parcial/test/test_solver_scenario.rb` (capacidad, bateria y dependencias, verificadas end-to-end sobre `scenario.json`).

## 16. Metodologia de validacion empirica

El diseno de las secciones anteriores no se dio por bueno solo por argumento en prosa: cada decision de poda se midio antes de adoptarse, siguiendo un principio simple -- no correr UCS completo a ciegas sobre el escenario real como metodo de prueba y error, porque una corrida sin instrumentacion que no termina no dice nada sobre *por que* no termina.

El proceso seguido fue:

1. **Diagnostico acotado antes que UCS completo.** Se construyo una exploracion con tope duro de expansiones (`test_search_diagnostic.rb`) que reporta cuantos estados unicos genera cada tipo de accion, sin ejecutar la busqueda por costo completa. Esto identifico que `DROP` era la accion dominante en la explosion de estados, antes de tocar una linea de poda.
2. **Escenarios sinteticos minimos para aislar cada regla.** Antes de validar una poda contra `scenario.json` (5 zonas, espacio de estados grande), se probo contra escenarios de 1 a 3 zonas construidos en memoria (`Scenario.new(hash)`, sin archivo) donde el comportamiento esperado es verificable a mano. `test_solver_smoke.rb` y `test_search_properties.rb` son el resultado de ese aislamiento.
3. **Comparacion cuantitativa de politicas alternativas**, no solo una intuicion sobre cual poda de `DROP` es "mas razonable". Se corrio el mismo `UcsSolver` con el mismo limite de expansiones bajo dos politicas (`needed_here` y `dead_only`, ver 7.1) y se comparo directamente: expansiones hasta converger, si converge, y el costo del plan encontrado. La decision de diseno (`dead_only` por defecto) se tomo con ese numero en mano, no antes.
4. **Corrida real end-to-end como criterio de aceptacion final**, no como primer paso. Solo despues de que las tres validaciones anteriores dieran resultados consistentes se corrio `UcsSolver` sobre `scenario.json` completo, con limite de expansiones explicito (no el limite de seguridad `MAX_EXPANSIONS` a ciegas).

Esta metodologia es replicable: los cuatro pasos corresponden a archivos de test versionados, no a corridas manuales descartadas.
9. **Contrato:** el plan formateado usa exclusivamente las operaciones visuales permitidas.

Este documento fija el comportamiento esperado. La siguiente etapa sera implementar cada componente en Ruby y probarlo contra `parcial/scenarios/scenario.json`.
