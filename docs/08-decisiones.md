# Decisiones de arquitectura

Registros cortos de decisión (ADR): **contexto → decisión → consecuencias**. Están en el
orden en que se tomaron, aproximadamente. Cada una es verificable en el código actual.

| # | Decisión |
|---|---|
| [ADR-01](#adr-01--supabase-como-backend-completo) | Supabase como backend completo, sin servidor propio |
| [ADR-02](#adr-02--retrofit-directo-contra-los-http-apis-sin-supabase-kt) | Retrofit directo contra los HTTP APIs, sin `supabase-kt` |
| [ADR-03](#adr-03--migraciones-sql-como-única-fuente-de-verdad) | Migraciones SQL como única fuente de verdad del esquema y la seguridad |
| [ADR-04](#adr-04--verificación-del-responsable-manual-y-fuera-de-la-app) | Verificación del responsable manual y fuera de la app |
| [ADR-05](#adr-05--grants-explícitos-por-tabla-en-cada-migración) | Grants explícitos por tabla en cada migración |
| [ADR-06](#adr-06--visión-ia-para-extraer-facturas-con-cupo-y-créditos-por-empresa) | Visión IA para extraer facturas, con cupo y créditos por empresa |
| [ADR-07](#adr-07--distribución-apk-directa-rama-para-play-y-binario-en-r2) | Distribución APK directa, rama para Play, binario en R2 |
| [ADR-08](#adr-08--sitio-estático-astro-y-admin-como-spa-separada-ambos-en-cloudflare) | Sitio estático Astro y admin como SPA separada, ambos en Cloudflare |
| [ADR-09](#adr-09--correlativo-atómico-en-postgres-y-períodoquincena-por-fecha-de-emisión) | Correlativo atómico en Postgres; período/quincena por fecha de emisión |
| [ADR-10](#adr-10--cobro-manual-con-reporte-de-pago-antes-que-pasarela) | Cobro manual con reporte de pago antes que pasarela |
| [ADR-11](#adr-11--créditos-prepagados-en-vez-de-suscripción) | Créditos prepagados en vez de suscripción |
| [ADR-12](#adr-12--lógica-fiscal-en-la-base-de-datos-con-espejo-probado-en-la-app) | Lógica fiscal en la base de datos, con espejo probado en la app |
| [ADR-13](#adr-13--realtime-sólo-en-el-admin-y-sin-transmitir-filas) | Realtime sólo en el admin y sin transmitir filas |
| [ADR-14](#adr-14--firma-y-sello-por-procesamiento-determinista-no-por-ia-generativa) | Firma y sello por procesamiento determinista, no por IA generativa |

---

### ADR-01 — Supabase como backend completo

**Contexto.** Un solo desarrollador, un producto con datos fiscales multi-tenant, la
necesidad de autenticación, archivos, lógica privilegiada y correo, y un presupuesto de
hosting que debía ser fijo y bajo.

**Decisión.** Usar Supabase como backend íntegro: Postgres (con RLS como modelo de
autorización), Auth, Storage, Edge Functions, tareas programadas y Realtime. Ningún
servidor de aplicación propio.

**Consecuencias.** La autorización vive en la base de datos y se aplica igual a cualquier
cliente; la lógica transaccional es SQL; el costo fijo es el plan Pro. A cambio, hay que
disciplinar las migraciones y los grants (ADR-03, ADR-05) y aceptar que Deno/TypeScript
es el runtime de las funciones. Un stack local completo en Docker permite probar todo sin
tocar producción.

### ADR-02 — Retrofit directo contra los HTTP APIs, sin `supabase-kt`

**Contexto.** Supabase expone Auth, PostgREST, Storage y Functions como HTTP normal. El
SDK de Kotlin añadía dependencias, su propio cliente HTTP y una capa de abstracción que
oculta cosas que aquí importan (timeouts largos para funciones con IA, refresh de token,
logging).

**Decisión.** Interfaces Retrofit por servicio, DTOs `snake_case` propios con
kotlinx-serialization, dos `OkHttpClient` (uno para autenticar sin authenticator y otro
con refresh silencioso ante 401), un tercero limpio para el manifiesto de actualización.

**Consecuencias.** Control fino del cliente HTTP y menos dependencias; hay que escribir
los DTOs y mappers a mano (los `toDomain()`), y mantener el `Authenticator` correcto
frente a concurrencia. La app queda desacoplada del ritmo de versiones del SDK.

### ADR-03 — Migraciones SQL como única fuente de verdad

**Contexto.** Cambios de esquema hechos a mano en producción son imposibles de auditar y
de reproducir en local.

**Decisión.** Todo (tablas, RLS, triggers, funciones, buckets, publicaciones) se define en
migraciones con marca de tiempo creadas con el CLI; nunca se editan las aplicadas; los
datos por entorno (secretos, programación de tareas, cuentas de cobro) quedan fuera del
repositorio.

**Consecuencias.** `db reset` reproduce producción en local en segundos; los scripts E2E
corren contra ese estado; cada decisión de seguridad tiene un archivo con su porqué. El
costo es escribir una migración nueva incluso para corregir una anterior.

### ADR-04 — Verificación del responsable manual y fuera de la app

**Contexto.** Un comprobante de retención tiene efectos ante el SENIAT. Permitir que
cualquiera opere a nombre de una empresa que no representa era el riesgo de fraude de
identidad más grave.

**Decisión.** La app sólo declara al responsable y aporta señales automáticas (lectura del
documento por IA, consulta del RIF). El estado "verificado" lo fija una persona desde el
panel admin y no puede escribirse desde el cliente. Sin verificación no hay emisión.

**Consecuencias.** Hay fricción en el onboarding (horas, no segundos) y una cola operativa
para el equipo; a cambio, la habilitación queda auditada y la IA nunca es la última
palabra. Un error de implementación en este control se detectó y se corrigió con una
migración dedicada, y dejó una regla de proyecto sobre cómo se escriben los triggers de
protección.

### ADR-05 — Grants explícitos por tabla en cada migración

**Contexto.** Las versiones recientes de la plataforma dejaron de otorgar privilegios
automáticos sobre tablas nuevas: una tabla con RLS perfecta devolvía 403 en local y en
proyectos nuevos. La alternativa fácil (privilegios por defecto para todo el esquema)
abría todas las tablas futuras sin querer.

**Decisión.** Cada migración que crea una tabla declara, en orden: tabla → RLS → políticas
→ grants. Al rol autenticado se le concede exactamente el comando que tiene política; las
tablas internas no reciben grant; el rol anónimo no recibe nada.

**Consecuencias.** Toda tabla nueva nace cerrada; el revisor ve en un solo archivo qué
puede hacer cada rol; hubo que pasar una migración de "puesta al día" por todas las
tablas existentes.

### ADR-06 — Visión IA para extraer facturas, con cupo y créditos por empresa

**Contexto.** El OCR clásico no entiende una factura venezolana (formatos libres,
talonarios, tickets térmicos, IGTF impreso). Un modelo de visión sí, pero cuesta dinero
por llamada y puede abusarse.

**Decisión.** Extraer con un modelo de visión desde una Edge Function que devuelve campos
sugeridos y **no persiste nada** (el usuario revisa siempre); exigir créditos antes de
llamar a la IA; cupo anti-abuso por empresa; telemetría de tokens y costo sin datos
personales. El modelo se elige por benchmark propio contra facturas reales.

**Consecuencias.** Precisión alta con revisión humana como red; el costo por factura es
marginal y está medido; el prompt y la lógica de normalización son parte del valor del
producto.

### ADR-07 — Distribución APK directa, rama para Play y binario en R2

**Contexto.** Google Play impone tiempos de revisión, restricciones sobre el cobro
embebido y una prueba cerrada previa. El público objetivo instala APKs con ayuda de su
contador o del propio equipo.

**Decisión.** Distribuir el APK firmado desde el sitio, con actualización in-app basada en
un manifiesto público (versión, URL, SHA-256, versión mínima, versión de términos). Una
rama separada del repositorio prepara la versión para Play sin cobro embebido. El binario
y el manifiesto viven en Cloudflare R2 con dominio propio.

**Consecuencias.** Releases en minutos y control total del ciclo; hay que educar sobre
"orígenes desconocidos" (la FAQ del sitio lo hace); una llave de firma irremplazable que
proteger; egress gratuito en R2 frente al costo de servir ~14 MB por descarga desde el
almacenamiento del backend.

### ADR-08 — Sitio estático Astro y admin como SPA separada, ambos en Cloudflare

**Contexto.** El sitio necesita SEO, velocidad y cero mantenimiento; el admin necesita
sesión, MFA y acceso restringido. Mezclarlos en una sola app no aportaba nada.

**Decisión.** Sitio en Astro con salida estática, un solo archivo de datos, deploy
automático por CI a Pages con validación previa del `dist/`. Admin como SPA React en Workers
Assets, detrás de Cloudflare Access, con su propia CSP.

**Consecuencias.** Dos pipelines simples e independientes; el catálogo de precios está
duplicado (sitio y backend) y se sincroniza a mano — es el punto de deriva más probable y
está señalado en ambos repos.

### ADR-09 — Correlativo atómico en Postgres y período/quincena por fecha de emisión

**Contexto.** El número de comprobante debe ser único, consecutivo por período y nunca
renumerarse; dos usuarios pueden emitir a la vez. Además, la providencia declara por
período de **emisión**, no por fecha de factura.

**Decisión.** Un contador por empresa y período que se incrementa con bloqueo de fila
dentro de la misma transacción que fija número, fecha, quincena y consumo del crédito;
unicidad por empresa y número como segunda barrera. Período y quincena se recalculan al
emitir por la fecha de emisión en hora de Venezuela. La primera emisión puede fijar el
número inicial.

**Consecuencias.** Sin colisiones ni huecos por concurrencia; anular no libera números;
el PDF se genera fuera de la transacción para que un fallo de PDF nunca pierda un número.

### ADR-10 — Cobro manual con reporte de pago antes que pasarela

**Contexto.** En Venezuela el pago habitual es pago móvil, transferencia en bolívares o
USDT; las pasarelas internacionales no aplican y las locales añaden costo y fricción para
un volumen inicial pequeño.

**Decisión.** La app muestra los datos de cobro (con QR) y el monto en Bs a tasa BCV; el
usuario paga por su banco y reporta con referencia, titular y captura; el equipo verifica
en el panel y acredita. Los datos de cobro se administran desde el panel, no en el
código.

**Consecuencias.** Cero comisiones y arranque inmediato; una cola operativa con alerta si
envejece; el circuito está diseñado para sustituirse por una pasarela sin cambiar el
modelo de créditos.

### ADR-11 — Créditos prepagados en vez de suscripción

**Contexto.** La primera versión del modelo era una suscripción mensual; el uso real es
irregular (picos de quincena) y las suscripciones exigen cobros recurrentes que el
circuito manual no soporta bien.

**Decisión.** 1 crédito = 1 comprobante emitido; paquetes escalonados en USD; prueba
gratis única por RIF; saldo por empresa con libro mayor inmutable; consumo dentro de la
transacción de emisión. Los planes de suscripción quedaron inactivos, no borrados
(hay pagos históricos que los referencian).

**Consecuencias.** El precio sigue al uso; la contabilidad interna es un ledger cuya
invariante se vigila; sin saldo la app no gasta IA ni emite.

### ADR-12 — Lógica fiscal en la base de datos, con espejo probado en la app

**Contexto.** Las reglas (quincena, cuadre, formato del número, validez de la fecha de
emisión, reglas de notas) deben ser inviolables desde cualquier cliente, pero el usuario
necesita ver el resultado al instante mientras escribe.

**Decisión.** La regla de verdad vive en funciones y triggers de Postgres. La app tiene
una copia en Kotlin puro (`domain/calc`), con tests JVM, que valida en el formulario; los
errores del servidor llegan con códigos estables que la app traduce a mensajes claros.

**Consecuencias.** UX inmediata y servidor autoritativo; la duplicación es consciente y
está acotada a funciones puras pequeñas con tests a ambos lados.

### ADR-13 — Realtime sólo en el admin y sin transmitir filas

**Contexto.** El panel necesita enterarse de pagos y responsables nuevos sin recargar; la
app no. Transmitir cambios de fila habría sacado datos personales por un canal más.

**Decisión.** Un canal privado de eventos "algo cambió", sin datos, al que sólo se
suscriben administradores; el panel refresca por la API normal bajo RLS. Sondeo periódico
de respaldo. La app consulta bajo demanda.

**Consecuencias.** Sin fuga posible de PII por Realtime, por construcción; una sola
suscripción por sesión; latencia de segundos, suficiente para una cola operativa.

### ADR-14 — Firma y sello por procesamiento determinista, no por IA generativa

**Contexto.** El comprobante lleva la firma y el sello del agente. La primera versión
recortaba la firma con un modelo generativo de imagen: lento, con costo y no
reproducible.

**Decisión.** Extraer firma y sello desde la foto de una hoja blanca con un algoritmo
determinista en el teléfono (estimación del blanco del papel, umbral de tinta por
oscuridad y saturación, limpieza de motas, recorte), sin red ni costo, con
previsualización antes de guardar.

**Consecuencias.** Resultado instantáneo y reproducible; el sello azul o rojo se conserva;
la imagen final es una sola PNG por empresa, en un bucket privado y sensible.

[← Volver al índice](../README.md)
