# PRD-AF-10 — `archinit --multi`: app modular de tres niveles lista en un comando

Ámbito: AppFoundation 1.2.0 · Origen: conversación con el propietario (2026-09-03) sobre modularizar
sin repetir el fracaso de «un paquete por feature» · Rompe API pública: no

## Problema

La recomendación para una app grande es modular por **targets**, no por manifiestos: pocos
`Package.swift`, muchos módulos. Hoy el kit solo prepara el caso «cáscara de app + un paquete
local con un módulo» (`archinit`), y `generate-feature --module` separa `XxxCore`/`XxxUI` pero
deja el alta del target en `Package.swift` como paso manual. Montar la estructura de tres niveles
a mano son ~40 ficheros y una docena de decisiones que ya están tomadas: debe ser un comando.

El antipatrón que evitamos, visto en producción: decenas de manifiestos, dependencias por rama,
SDKs pesados compilados desde fuente y un `Core` del que depende todo. Resultado: minutos al
cambiar de scheme y previews rotas. Este PRD deja la alternativa lista y vigilada por el linter.

## La estructura que deja

```
<repo>/
├── project.yml                     xcodegen: app + tests + UI tests; depende de Platform, Features,
│                                   AppFoundation y CoreNetworking (los transitivos, a mano: fricción 6)
├── App/                            cáscara: <Name>App.swift (@main, Firebase/config), RootView.swift,
│                                   AppModule.swift (composition root), Assets, Info.plist
├── AppTests/  AppUITests/          smoke del composition root + XCUITest de arranque (offline)
├── Packages/
│   ├── Platform/Package.swift      3 targets + tests:
│   │   ├── Sources/Domain          modelos y protocolos compartidos; solo Foundation
│   │   ├── Sources/<Cap>Kit        una por --capability (p. ej. CameraKit): implementa un protocolo de Domain
│   │   └── Sources/<Sdk>Adapters   una por --adapter (p. ej. FirebaseAdapters): el ÚNICO import del SDK
│   └── Features/Package.swift      un target por feature + su test target; markers archinit para el alta automática
│       └── Sources/<Name>Feature   (vacío hasta el primer generate-feature)
├── .archlint.yml (raíz, reglas de dependencia entre módulos) · Packages/*/.archlint.yml (reglas de capa)
├── .swiftlint.yml · .swift-format · AGENTS.md · CLAUDE.md · .claude/skills/feature.md
└── .github/workflows/ci.yml        matriz por paquete (swift test) + xcodebuild test de la app
```

Dependencias permitidas (la tabla se genera en `AGENTS.md` y se aplica como regla R13):

| Módulo | Puede importar | Nunca importa |
|---|---|---|
| Domain | Foundation | nada más |
| `<Cap>Kit` | Domain + frameworks del sistema | features, adapters, SDKs |
| `<Sdk>Adapters` | Domain + el SDK | features |
| `<Name>Feature` | AppFoundation, CoreNetworking, Domain | otra feature, cualquier SDK, cualquier Kit |
| App | todo | lógica de negocio |

## Arranque (el único paso manual, documentado)

Un command plugin solo corre sobre un paquete que dependa de AppFoundation, así que en un repo
vacío hace falta un manifiesto mínimo antes de invocarlo:

```bash
mkdir -p Packages/Features && cat > Packages/Features/Package.swift <<'EOF2'
// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "Features", dependencies: [
    .package(url: "https://github.com/hiramvazquez/AppFoundation.git", from: "1.2.0")
])
EOF2
cd Packages/Features && swift package --allow-writing-to-package-directory archinit --multi \
    --root ../.. --name MiApp --capability Camera --adapter Firebase
```

`archinit --multi` reescribe ese manifiesto con la forma final (markers incluidos) y genera todo lo
demás. Alternativa sin paso manual: `Scripts/bootstrap-multi.sh <Name>` en el paquete, que hace
esas cinco líneas y llama al plugin; se documenta como camino corto.

## Entregables

1. **`archinit --multi`** (`Plugins/ArchInit`): opciones `--root <dir>` (raíz del repo; por defecto
   el padre de `Packages/`), `--name <App>`, `--bundle-id`, `--capability <Cap>` (repetible),
   `--adapter <Sdk>` (repetible; `Firebase` trae la dependencia y un adapter de ejemplo para
   `AnalyticsTracking`/`CrashReporting` con `#if canImport(FirebaseAnalytics)`), `--no-xcodegen`,
   `--dry-run`. Idempotente: nunca pisa un fichero existente (misma política que hoy), imprime
   el diff sugerido. Plantillas nuevas en `Templates/Multi/` (texto, mismo motor `{{…}}`).
2. **`generate-feature` consciente del modo multi.** Detecta `Packages/Features/Package.swift` con
   los markers `// archinit:features-begin` / `// archinit:features-end` y, además de generar
   `Sources/<Name>Feature/…` y `Tests/<Name>FeatureTests/…`, **da de alta el target y su test
   target entre los markers** (única edición de manifiesto que hace el generador; `--no-register`
   la desactiva). Fuera del modo multi, comportamiento actual sin cambios. `--module` en modo
   multi genera `<Name>FeatureCore` + `<Name>FeatureUI` como dos targets reales.
3. **Regla R13 del linter — aislamiento entre módulos.** `.archlint.yml` de la raíz gana
   `modules:` con, por módulo, `allowedImports:` y `forbiddenImports:` (globs; `*Feature`,
   `Firebase*`). `archlint` deduce el módulo del fichero por su ruta `Sources/<Target>/`. Error:
   «`MisCasosFeature` no puede importar `IndemnizacionesFeature`: las features se comunican por
   Domain y por `AppRoute`». El build-tool plugin ya recibe el target; el command plugin lo
   calcula por ruta. Tests con fixtures multi-target.
4. **Composition root generado**: `App/AppModule.swift` registra `Domain` (nada), los Kits, los
   Adapters y un `register(modules:)` con un `// archinit:modules` marker donde `generate-feature`
   añade `<Name>Module()`; `RootView` con `Coordinator<AppRoute>` y un `AppRoute` con marker para
   los `case` nuevos (el generador ya imprime ese paso; en modo multi lo hace).
5. **xcodegen y CI**: `project.yml` con la app dependiendo de ambos paquetes locales y de los kits
   transitivos, `UI_TEST_OFFLINE` horneada, schemes de paquetes ocultos; `ci.yml` con matriz
   `package: [Platform, Features]` → `swift test` + `swift package archlint`, y un job de app
   con `xcodebuild test -skipPackagePluginValidation`; SwiftLint estricto por paquete.
6. **Docs**: artículo `MultiModule.md` (por qué targets y no paquetes, la tabla de dependencias,
   el arranque, cómo migrar una app existente en cinco pasos: Domain → mover módulos como
   targets → linter en aviso → features nuevas con el generador → adapters al final), sección en
   `GettingStarted.md`, README, `AGENTS.md` (la tabla de dependencias se genera con los nombres
   reales del proyecto), `feature.skill.md`.
7. **`Scripts/verify-multi.sh`** (y job `multi` en CI): en un directorio temporal, arranque
   manual + `archinit --multi --capability Camera --adapter Firebase`, `generate-feature
   Contratos --api`, `generate-feature MisCasos --api --local`, `swift build`/`swift test` de
   ambos paquetes, `archlint` limpio; después un `import ContratosFeature` dentro de MisCasos
   → el build FALLA con `[ArchLint.R13]`; se revierte; si `xcodegen` está en el PATH, genera el
   proyecto y `xcodebuild build` de la app. Transcripción en el informe.

## Decisiones cerradas (para no reabrirlas)

- Dos manifiestos locales, no uno por feature. Un tercero solo si aparece `DesignSystem` (PRD aparte).
- Los SDKs entran por adapters con protocolo en Domain; una feature que importe un SDK es error de build.
- Las features no se importan entre sí; navegan por `AppRoute` y comparten por Domain.
- `Package.resolved` versionado; dependencias por tag, nunca por rama (R14, aviso: `branch:`/`revision:` en un manifiesto).
- El generador edita `Package.swift` solo entre markers y solo en modo multi.

## Criterios de aceptación
- [ ] `verify-multi.sh` en verde local y en CI (incluida la prueba negativa R13).
- [ ] Un repo recién creado con el arranque documentado abre en Xcode, resuelve en segundos, compila la app y muestra las previews de una feature generada.
- [ ] `archinit` sin `--multi` no cambia de comportamiento (verify-generator.sh sigue en verde).
- [ ] Docs: `MultiModule.md`, `GettingStarted.md`, README, `AGENTS.md` generado con la tabla real.
- [ ] Verificación completa del paquete y tag `1.2.0` tras CI verde. Después, migrar AppStarter al modo multi como prueba real (PRD-APP-02).

## Fuera de alcance
- `DesignSystem` como kit publicado (tokens, estilos de `ScreenContainer`): PRD propio.
- Migración automática de código existente: el artículo la describe, el comando no la hace.
- Contenido real de los adapters más allá del ejemplo de Firebase Analytics/Crashlytics.

## Ficheros
`AppFoundation/Plugins/ArchInit/plugin.swift`, `AppFoundation/Plugins/GenerateFeature/plugin.swift`,
`AppFoundation/Sources/GenerateFeatureSupport/**` (markers), `AppFoundation/Sources/archlint/{Config,Model,Rules}.swift` (R13, R14),
`AppFoundation/Templates/Multi/**`, `AppFoundation/Scripts/verify-multi.sh`, `AppFoundation/Tests/{ArchLintTests,GenerateFeatureSupportTests}/**`,
`AppFoundation/Sources/AppFoundation/Documentation.docc/{MultiModule,GettingStarted,AppFoundation}.md`,
`AppFoundation/{README,AGENTS,CHANGELOG}.md`, `AppFoundation/Templates/feature.skill.md`, `AppFoundation/.github/workflows/ci.yml`.
