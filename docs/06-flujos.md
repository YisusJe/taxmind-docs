# Flujos

Siete secuencias que cubren la vida de una empresa en TaxMind: desde el registro hasta la
declaración de la quincena, pasando por los pagos y la colaboración. En todos los
diagramas los participantes se nombran **por rol** ("Extracción", "Emisión", "Base de
datos"), no por el nombre de ninguna función o tabla.

| # | Flujo | Quién lo vive |
|---|---|---|
| 1 | [Onboarding](#1-onboarding) | admin de una empresa nueva |
| 2 | [Foto → extracción → comprobante](#2-foto--extracción--comprobante) | cualquier miembro |
| 3 | [Notas de crédito y débito](#3-notas-de-crédito-y-débito) | cualquier miembro |
| 4 | [Cierre de quincena y TXT SENIAT](#4-cierre-de-quincena-y-txt-seniat) | quien declara; admin para anular |
| 5 | [Créditos y pagos](#5-créditos-y-pagos) | admin de la empresa + equipo TaxMind |
| 6 | [Actualización de la app](#6-actualización-de-la-app) | cualquier usuario |
| 7 | [Colaboración multiempresa](#7-colaboración-multiempresa) | admin + invitado |

---

## 1. Onboarding

Del registro a poder emitir. La pieza clave es que **la app sólo declara** al responsable
legal; la habilitación la hace una persona desde el panel, con las señales automáticas
como apoyo (ver [Seguridad §4](05-seguridad.md#4-verificación-del-responsable-legal-fuera-de-la-app)).

<!-- mmd:09-flujo-onboarding.mmd -->
```mermaid
%% Flujo 1 — Onboarding: del registro a poder emitir comprobantes
sequenceDiagram
  autonumber
  actor U as Admin de la empresa
  participant App as App Android
  participant Auth as Auth
  participant DB as Base de datos
  participant Sen as Señales (IA · SENIAT)
  participant Eq as Equipo TaxMind (panel)

  U->>App: Registro (nombre, correo, contraseña, acepta términos)
  App->>Auth: Crear cuenta
  Auth-->>U: Código de confirmación por correo
  U->>App: Ingresa el código
  App->>Auth: Verificar → sesión

  U->>App: Crear empresa (RIF, razón social, dirección) — o unirse con código
  App->>DB: Crear empresa + membresía admin (una transacción)
  DB->>Sen: Consulta del RIF en el SENIAT (señal, en segundo plano)
  DB-->>App: Empresa creada (prueba gratis de créditos asignada)

  U->>App: Declarar responsable legal (documento + foto)
  App->>DB: Guardar responsable → estado "pendiente"
  App-)Sen: Lectura del documento por IA (señal, no bloqueante)
  DB-)Eq: Aviso: responsable pendiente de verificación
  Note over App: El Home muestra "pendiente" y<br/>"Nueva retención" queda deshabilitada

  Eq->>DB: Revisa documento, datos y señales → verifica (o rechaza con motivo)
  DB-)U: Correo: responsable verificado / rechazado
  U->>App: Vuelve a la app
  App->>DB: Estado del responsable
  DB-->>App: verificado
  Note over App: "Nueva retención" habilitada.<br/>Opcional: subir firma y sello para el PDF.
```

Notas:

- La cuenta se confirma con un código de un solo uso enviado por correo (no con un
  enlace), pensado para un flujo 100 % móvil.
- Crear la empresa asigna la prueba gratis de créditos (una sola vez por RIF).
- Mientras el responsable está pendiente, la empresa ya puede registrar facturas y
  proveedores; sólo la **emisión** queda bloqueada.
- Un usuario que se une con código de invitación entra directo a una empresa ya
  configurada y se salta la declaración del responsable.

---

## 2. Foto → extracción → comprobante

El flujo central del producto: de una foto a un comprobante con correlativo en menos de
un minuto.

<!-- mmd:10-flujo-foto-comprobante.mmd -->
```mermaid
%% Flujo 2 — De la foto de la factura al comprobante emitido
sequenceDiagram
  autonumber
  actor U as Usuario
  participant App as App Android
  participant St as Storage
  participant Ext as Extracción (IA)
  participant DB as Base de datos
  participant Em as Emisión (PDF)

  U->>App: Foto de la factura (cámara o galería)
  App->>App: Comprime la imagen (menos de 1 MB, corrige rotación)
  App->>St: Sube la foto (carpeta de la empresa)
  App->>Ext: Extraer campos de esta foto
  Ext->>DB: ¿Tiene créditos? ¿Dentro del cupo?
  Ext->>Ext: Visión IA → RIF, razón social, número, fecha, bases, IVA, IGTF, total
  Ext-->>App: Campos sugeridos (nada se guarda todavía)

  U->>App: Revisa y corrige, alta del proveedor si es nuevo
  App->>App: Cálculo local: 75 % / 100 % del IVA, cuadre con IGTF aparte, quincena
  alt Factura 100 % exenta
    App->>DB: Registrar como "exenta" (sin comprobante, sin crédito)
  else Factura con IVA
    App->>DB: Guardar factura + retención "pendiente"
    U->>App: Emitir (fecha de emisión, nº inicial sólo la primera vez)
    App->>Em: Emitir esta retención
    Em->>DB: Función atómica: correlativo + número + fecha + quincena + consumo de crédito
    DB-->>Em: Número de comprobante (todo o nada)
    Em->>St: Genera el PDF con firma y sello y lo guarda
    Em-->>App: Comprobante emitido (si el PDF falló, se regenera al reintentar)
    App-->>U: Ver · compartir · guardar el PDF
  end
```

Notas:

- La imagen se comprime en el teléfono (tamaño máximo, lado mayor acotado, rotación
  EXIF corregida) antes de subir; las facturas térmicas largas usan un lado mayor más
  generoso.
- La extracción **no guarda nada**: devuelve campos sugeridos y el usuario siempre revisa.
  El IGTF se detecta y se separa del IVA; las series de talonario se combinan con el
  número; hay un cupo por empresa y una espera visible si se supera.
- El cálculo (75 % o 100 % del IVA según la empresa, con override por retención; cuadre
  del total con IGTF aparte; período y quincena) se hace en el teléfono para mostrarlo al
  instante y **se repite en el servidor** al emitir.
- Una factura 100 % exenta se registra como tal: queda en el historial sin comprobante,
  sin correlativo y sin gastar crédito.
- La emisión es **una transacción**: correlativo, número, fecha, quincena y consumo del
  crédito, o nada. El PDF se genera después y se guarda; si falla, el número ya asignado
  no se pierde y el reintento sólo regenera el PDF. El PDF lleva la firma y el sello de la
  empresa si los subió.
- La primera emisión de la empresa permite fijar el número inicial para continuar la
  numeración de un sistema anterior; después es automático.

---

## 3. Notas de crédito y débito

Una nota se registra como un documento más, ligado a la factura original, y sigue el
mismo circuito de emisión.

<!-- mmd:15-flujo-notas-credito-debito.mmd -->
```mermaid
%% Flujo 3 — Notas de crédito y débito ligadas a la factura original
sequenceDiagram
  autonumber
  actor U as Usuario
  participant App as App Android
  participant DB as Base de datos
  participant Em as Emisión (PDF)

  U->>App: Nueva retención → tipo "nota de crédito" (o débito)
  App->>DB: Buscar facturas afectables del proveedor (emitidas, misma empresa)
  U->>App: Elige la factura afectada e ingresa los montos de la nota
  App->>App: Valida en local: misma quincena que la factura, NC ≤ total de la factura
  App->>DB: Guardar nota (tipo de documento + enlace a la factura afectada)
  DB->>DB: Valida de nuevo: misma empresa y proveedor, misma quincena,<br/>tope acumulado de NC vigentes ≤ total de la factura
  alt Regla incumplida
    DB-->>App: Error con código estable → mensaje claro al usuario
  else OK
    U->>App: Emitir
    App->>Em: Emitir la retención de la nota
    Em->>DB: Correlativo propio, mismo circuito que una factura
    Em-->>App: Comprobante de la nota (PDF con montos de NC en negativo)
  end
  Note over App,DB: En el TXT y el resumen de quincena la NC resta.<br/>Los montos se guardan en positivo y el signo se aplica al reportar.
```

Notas:

- La factura afectada debe ser de la misma empresa y proveedor y estar en la **misma
  quincena** (el SENIAT rechaza un TXT con una nota "aislada").
- Las notas de crédito acumuladas no pueden superar el total de la factura; tampoco se
  puede reducir después el total de una factura que ya tiene notas.
- La nota tiene su propio comprobante y correlativo; en el PDF, el TXT y el resumen de
  quincena una nota de crédito aparece en negativo.

---

## 4. Cierre de quincena y TXT SENIAT

<!-- mmd:11-flujo-txt-seniat.mmd -->
```mermaid
%% Flujo 4 — Cierre de quincena, TXT para el SENIAT y anulaciones posteriores
sequenceDiagram
  autonumber
  actor U as Usuario
  participant App as App Android
  participant DB as Base de datos
  participant Txt as Exportación TXT
  participant SEN as Portal SENIAT

  Note over App: 2 días antes del cierre: recordatorio local<br/>con las retenciones pendientes de emitir
  U->>App: Historial → elige mes y quincena
  App->>DB: Resumen de la quincena (emitidas, notas, totales)
  U->>App: Exportar TXT
  App->>Txt: Generar TXT de la quincena
  Txt->>DB: Retenciones emitidas del período de emisión (bajo RLS del usuario)
  Txt-->>App: Archivo de 16 columnas (NC en negativo, IGTF excluido)
  U->>SEN: Declara con el TXT (fuera de TaxMind)
  U->>App: Marcar quincena como declarada
  App->>DB: Registrar la declaración (filas, total, fecha) — cierre suave

  opt Anular un comprobante después de declarar
    U->>App: Anular con motivo (sólo admin)
    App->>DB: Anular
    DB-->>App: La quincena ya fue declarada: ¿confirmar?
    U->>App: Confirma
    App->>DB: Anular marcando "post-declaración"
    Note over DB: Conserva número y PDF, el correlativo no se renumera.<br/>Queda evidencia de que hace falta declaración sustitutiva.
  end
```

Notas:

- El TXT sigue la guía oficial (16 columnas, tabulado, sin encabezado), agrupa por
  **período de emisión** y excluye el IGTF del total de la factura.
- "Marcar como declarada" es un **cierre suave**: registra cuándo se declaró y con qué
  totales, sin renumerar ni congelar nada. Puede repetirse (declaraciones sustitutivas).
- Anular después de declarar pide confirmación explícita y deja marca de
  "post-declaración"; el número y el PDF se conservan.
- Un recordatorio local (WorkManager) avisa dos días antes del cierre si hay pendientes,
  con acceso directo al historial filtrado.

---

## 5. Créditos y pagos

Modelo prepago sin pasarela: la empresa paga por su banco y reporta; el equipo verifica y
acredita.

<!-- mmd:12-flujo-creditos-pagos.mmd -->
```mermaid
%% Flujo 5 — Créditos y pagos: del paquete a la acreditación
sequenceDiagram
  autonumber
  actor U as Admin de la empresa
  participant App as App Android
  participant DB as Base de datos
  participant Eq as Equipo TaxMind (panel)
  participant Tasa as Tasa BCV (programada)

  Note over Tasa,DB: Dos veces al día: sincroniza la tasa oficial USD/Bs<br/>(fuente + respaldo, rechaza saltos anómalos)

  U->>App: Créditos → elige un paquete
  App->>DB: Catálogo de paquetes, datos de cobro activos, tasa vigente
  App-->>U: Total en USD (con IVA/IGTF si pide factura) y en Bs a tasa BCV, QR de pago
  U->>App: Paga por su banco y reporta: método, referencia, titular, captura
  App->>DB: Guardar pago "reportado" (la app no puede marcarlo verificado)
  DB-)Eq: Correo: pago reportado (con captura y enlace al panel)

  Eq->>DB: Revisa y verifica (o rechaza con motivo)
  DB->>DB: Acredita créditos: saldo + movimiento en el libro mayor (misma transacción)
  App-->>U: Aviso: pago verificado (la app sondea el estado en primer plano)

  Note over U,DB: Consumo: 1 crédito por comprobante emitido,<br/>dentro de la transacción de emisión. Sin saldo → 402 y la app lleva a Créditos.
```

Notas:

- La app muestra el total en USD y en bolívares a la **tasa oficial del día**, que una
  tarea programada sincroniza dos veces al día (con fuente de respaldo y rechazo de
  variaciones anómalas); si la tasa tiene más de una semana, no se muestra el monto en Bs.
- El reporte exige captura y, para pago móvil, los datos del titular; el pago nace
  siempre como "reportado" aunque la app intente otra cosa.
- La verificación y la acreditación son del panel; la acreditación escribe saldo y libro
  mayor en la misma transacción, y es la única vía de sumar créditos.
- La app avisa con una notificación cuando el pago pasa a verificado o rechazado, y
  puede generar un PDF informativo del pago verificado.

---

## 6. Actualización de la app

<!-- mmd:16-flujo-actualizacion-app.mmd -->
```mermaid
%% Flujo 6 — Actualización de la app instalada (distribución fuera de Play)
sequenceDiagram
  autonumber
  participant App as App Android
  participant R2 as Cloudflare R2 (dominio de descargas)
  actor U as Usuario
  participant OS as Android

  App->>R2: Al arrancar: leer el manifiesto (latest.json)
  R2-->>App: versión publicada, URL del APK, SHA-256,<br/>versión mínima soportada, versión de términos
  alt Instalada es la publicada o más nueva
    Note over App: Nada que hacer
  else Instalada más vieja, pero aún soportada
    App-->>U: Aviso opcional ("Más tarde" lo pospone)
  else Instalada por debajo de la mínima soportada
    App-->>U: Aviso obligatorio: la app se bloquea hasta actualizar
  end
  U->>App: Actualizar
  App->>OS: Abre la URL del APK en el navegador
  OS->>R2: Descarga el APK
  U->>OS: Instala encima (misma firma, versionCode mayor)
  Note over App: La sesión se conserva.<br/>Si el manifiesto trae una versión de términos nueva,<br/>la app pide re-aceptarlos.
```

Notas:

- El manifiesto y el APK viven en Cloudflare R2 bajo un dominio propio, con URLs
  estables que se sobrescriben en cada versión; el sitio publica versión, fecha, tamaño y
  SHA-256 para que cualquiera verifique su descarga.
- La versión mínima soportada permite retirar versiones rotas contra el backend sin
  esperar a que el usuario actualice por su cuenta.
- El mismo manifiesto transporta la versión vigente de los términos: subirla obliga a
  re-aceptarlos en la app.

---

## 7. Colaboración multiempresa

<!-- mmd:17-flujo-colaboracion.mmd -->
```mermaid
%% Flujo 7 — Colaboración multiempresa: invitaciones, roles y avisos
sequenceDiagram
  autonumber
  actor A as Admin de la empresa
  participant App as App Android
  participant DB as Base de datos
  actor B as Usuario invitado
  participant Correo as Correo

  A->>App: Miembros → generar invitación (rol admin u operador, correo esperado)
  App->>DB: Crear invitación
  DB-->>App: Código de un solo uso (se guarda sólo su hash, vence en 7 días)
  A-->>B: Comparte el código (WhatsApp, en persona…)

  B->>App: Empresas → "Unirse con código"
  App->>DB: Canjear código
  DB->>DB: Límite de intentos por usuario, código inexistente, vencido,<br/>revocado o usado responden igual
  DB-->>App: Membresía creada con el rol de la invitación
  DB-)Correo: Aviso a los admins: alguien se unió a la empresa
  B->>App: Trabaja en la empresa (según su rol)

  opt Gestión posterior (sólo admin)
    A->>App: Cambiar rol · quitar miembro · revocar invitación pendiente
    App->>DB: Aplicar (nunca puede quedar la empresa sin admin)
    DB->>DB: Auditoría por empresa
  end
```

Notas:

- El código es aleatorio y de un solo uso, con vencimiento; sólo se guarda un *hash* y se
  muestra en claro una única vez.
- El canje tiene límite de intentos y no revela si un código existe, venció o fue
  revocado.
- Roles: **admin** (todo) y **operador** (registrar y emitir). Nunca puede quedar una
  empresa sin admin. Los cambios de miembros y las invitaciones quedan en la auditoría de
  la empresa y hay un feed de actividad para los admins.

[← Volver al índice](../README.md)
