# Remote iOS Build: инструкция для агента

Этот файл можно передать агенту в любом Swift/iOS-проекте. Он задаёт порядок
работы, а не фиксированную команду сборки. Все значения в угловых скобках нужно
заменить данными нового проекта. Секретов в этом документе быть не должно.

## Задача

Ты работаешь с исходниками на локальном компьютере, но собираешь iOS-приложение
на другом Mac по SSH. Прочитай инструкции репозитория, проверь удалённое
окружение, синхронизируй необходимые изменения, собери и подпиши приложение,
проверь результат и верни артефакты на локальный компьютер.

Не ограничивайся описанием команд, если пользователь попросил выполнить сборку.
Не объявляй задачу завершённой, пока не проверен полученный артефакт. Если нужна
ручная авторизация, дай одну точную команду и продолжи после её выполнения.
Пароли пользователь вводит в своём терминале, не в переписке с агентом.

## 1. Параметры проекта

Сначала заполни эту таблицу из репозитория, CI-конфигурации и данных пользователя.
Спрашивай только то, что не удалось установить. Не переноси адреса, сертификаты
или номера сборок из другого проекта.

| Параметр | Значение |
| --- | --- |
| SSH-хост | `<user@build-mac.local>` или настроенный SSH alias |
| Локальный корень репозитория | `<LOCAL_REPO>` |
| Корень репозитория на Mac-сборщике | `<REMOTE_REPO>` |
| Способ сборки | существующий скрипт / Fastlane / Xcode / Tuist / XcodeGen / Bazel |
| Версия и расположение Xcode | `<DEVELOPER_DIR>` |
| Workspace или project | `<App.xcworkspace>` или `<App.xcodeproj>` |
| Shared scheme и конфигурация | `<SCHEME>`, `<CONFIGURATION>` |
| Bundle ID приложения и расширений | `<BUNDLE_IDS>` |
| Apple Developer Team | `<TEAM_ID>` |
| Режим подписи | automatic / manual, сертификаты и профили для всех app targets |
| Способ распространения | устройство разработчика / зарегистрированные устройства / TestFlight / App Store |
| Номер сборки | `<BUILD_NUMBER>`, согласованный с пользователем или CI |
| Keychain на сборщике | `<SIGNING_KEYCHAIN>`, без пароля |
| Identity для проверки подписи | `<SIGNING_IDENTITY>`, SHA-1 или полное имя |
| ExportOptions | путь к проверенному `ExportOptions.plist`, если нужен |
| Каталог кэша | отдельный для проекта и совместимого toolchain |
| Артефакты | отдельный каталог для каждого запуска на обоих компьютерах |
| Установка | нужна ли; к какому компьютеру подключён iPhone; его UDID |

Сборка Swift package, simulator build и подписанный iPhone IPA не взаимозаменяемы.
`swift build` сам по себе не создаёт устанавливаемое iOS-приложение.

## 2. Правила безопасности

- Прочитай `AGENTS.md`, README, документацию сборки, CI и существующие скрипты.
- Сначала используй штатный процесс проекта. Не заменяй его новым ради шаблона.
- Сохраняй чужие незакоммиченные изменения на обоих компьютерах. Не выполняй
  `git reset --hard`, принудительный checkout, `git clean` или автоматический stash.
- Не коммить и не пушь изменения без запроса пользователя.
- Не выводи приватные ключи, `.p12`, пароли, токены, API secrets и содержимое
  секретных конфигураций. Не извлекай пароли из shell history или чужих файлов.
- Не отключай проверку SSH host key. Новый ключ хоста нужно проверить и подтвердить.
- Не запускай `clean` и не удаляй DerivedData, Pods или Bazel cache первым шагом.
- Не меняй глобальный Xcode через `sudo xcode-select` без необходимости:
  предпочитай `DEVELOPER_DIR` для конкретного процесса.
- Не сбрасывай keychain и не отзывай сертификаты. Не меняй глобально доверие к ним.
- Изменения keychain ACL, search list, signing assets и Apple Developer account
  требуют отдельного согласования. Не добавляй entitlement, которого нет в профиле.
- Не устанавливай приложение, не выходи из аккаунтов и не публикуй IPA по внешней
  ссылке, если пользователь запросил только сборку.
- Если окружение запрещает SSH или другую операцию, запроси предусмотренное
  разрешение. Не обходи отказ другим инструментом.

## 3. Найди реальный способ сборки

Проверь `git status`, текущую ревизию, submodules, `Package.resolved`, `Podfile.lock`,
`Gemfile.lock`, `fastlane/`, `Makefile`, CI и скрипты. Определи, какие проектные
файлы генерируются и какой командой. Для CocoaPods обычно нужен workspace.

Если уже есть рабочая CI lane или build script, выясни его входные параметры,
режим подписи, выходные файлы и используй его. Команды Xcode ниже нужны только
когда у проекта нет более подходящего процесса.

Не обновляй версии зависимостей ради сборки. Используй lock-файлы и закреплённые
версии инструментов. `pod install` и `pod update` решают разные задачи.
Проверь доступ сборщика к приватным зависимостям, не копируя секреты в исходники.

## 4. Проверь Mac-сборщик

Ниже `BUILD_HOST`, `LOCAL_REPO` и `REMOTE_REPO` задаются на локальном компьютере:

```bash
BUILD_HOST='<user@build-mac.local>'
LOCAL_REPO='<absolute local repository path>'
REMOTE_REPO='<absolute remote repository path>'

ssh -o BatchMode=yes -o ConnectTimeout=10 "$BUILD_HOST" 'sw_vers'
```

Первое подключение и настройку SSH-доступа при необходимости выполняет
пользователь. Не считай произвольный доступный сервер Mac-сборщиком.

Подключись к сборщику и запускай следующие shell-примеры в Bash. Локальные
переменные через SSH автоматически не передаются: задай их заново на сборщике.

```bash
ssh -t "$BUILD_HOST"
```

На удалённом Mac:

```bash
bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DEVELOPER_DIR='<absolute path to Xcode.app/Contents/Developer>'
REMOTE_REPO='<absolute remote repository path>'
cd "$REMOTE_REPO"

sw_vers
uname -m
xcode-select -p
xcodebuild -version
xcodebuild -showsdks
xcrun --find swift
df -h .
git rev-parse HEAD
git status --short
```

Проверь полный Xcode, нужный SDK, совместимость проекта и свободное место.
Одних Command Line Tools может быть недостаточно. После установки Xcode могут
понадобиться принятие лицензии и первоначальная настройка: это действие
администратора, а не повод автоматически выполнять произвольные sudo-команды.
Не загружай чужой `.zshrc` вслепую для исправления PATH.

Для стандартного Xcode-проекта выбери ровно один контейнер:

```bash
CONTAINER_ARGS=(-workspace '<relative path/App.xcworkspace>')
# Если workspace не используется, вместо предыдущей строки:
# CONTAINER_ARGS=(-project '<relative path/App.xcodeproj>')

xcodebuild "${CONTAINER_ARGS[@]}" -list -json
```

Scheme должна быть доступна на сборщике, обычно через shared scheme. Проверь
Archive action, конфигурацию, app target и включённые extensions. `-list` может
потребовать доступ к зависимостям. Не печатай весь `-showBuildSettings` в общий
лог, если проект содержит секреты в build settings.

## 5. Синхронизируй исходники

Сравни ревизии и dirty worktree на обоих компьютерах. Если удалённой копии ещё
нет, создай checkout согласованной ревизии вместе с нужными submodules.
Не клонируй поверх существующего каталога.

Для чистой закоммиченной версии можно использовать Git. Незакоммиченные правки
передавай ограниченным списком файлов или через проверенный rsync. Не теряй
новые untracked исходники, ресурсы, project files и lock-файлы.

Пример предварительного просмотра из локального Bash:

```bash
SYNC_FILTERS=(
  --exclude='.git/'
  --exclude='.build/'
  --exclude='DerivedData/'
  --exclude='build-artifacts/'
  --exclude='.DS_Store'
)
# Дополнительно исключи реальные каталоги ключей, .env и локальных секретов.
# Quoting для remote shell; не используй этот вариант с rsync --protect-args.
printf -v REMOTE_DEST_Q '%q' "$REMOTE_REPO/"

rsync -av --dry-run "${SYNC_FILTERS[@]}" \
  "$LOCAL_REPO/" "$BUILD_HOST:$REMOTE_DEST_Q"
```

Это не готовый универсальный ignore list. Перед запуском дополни его по проекту.
Не исключай все `.xcworkspace`, `.swiftpm` или `Pods` автоматически: часть их
содержимого может быть обязательной для конкретного репозитория.

После просмотра передай только нужные файлы. При возможном конфликте сравни
содержимое и сохрани резервную копию изменяемых удалённых файлов. Не используй
`--delete`. Не перезаписывай удалённые signing assets и локальные настройки
сборщика. Для изменённого файла Git HEAD недостаточно: сравни также SHA-256 или diff.

Один shared worktree нельзя одновременно синхронизировать и собирать разными
задачами. На время сборки зафиксируй набор исходников. Для параллельных сборок
используй отдельные checkout/worktree и каталоги артефактов.

## 6. Проверь подпись до долгой сборки

На сборщике проверь наличие подходящей identity:

```bash
security find-identity -v -p codesigning
```

Сертификат должен иметь доступный private key. Наличие identity в списке ещё
не доказывает, что SSH-сессия может подписывать. Для каждого app/extension target
проверь Team, Bundle ID, профиль, срок действия, capabilities и способ установки.
Если профиль ограничен устройствами, UDID нужного iPhone должен быть включён.

В той же интерактивной SSH-сессии, где пойдёт сборка:

```bash
SIGNING_KEYCHAIN='<absolute keychain path>'
SIGNING_IDENTITY='<certificate SHA-1 or exact identity name>'

security unlock-keychain "$SIGNING_KEYCHAIN"

PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ios-signing-probe.XXXXXX")"
cp /usr/bin/true "$PROBE_DIR/SigningProbe"
codesign --force --sign "$SIGNING_IDENTITY" \
  --keychain "$SIGNING_KEYCHAIN" --timestamp=none "$PROBE_DIR/SigningProbe"
codesign --verify --strict "$PROBE_DIR/SigningProbe"
```

Не передавай пароль через `-p`, переменную командной строки, history или чат.
Если signing preflight не проходит, сначала реши проблему с доступом к ключу.
Не повторяй полную сборку десятки раз.

Для manual signing используй настройки проекта и соответствие профилей всем
Bundle ID. Не задавай один `PROVISIONING_PROFILE_SPECIFIER` глобально всем
таргетам: расширениям могут требоваться другие профили.

Для automatic signing нужны права и настроенная авторизация Apple на сборщике.
`-allowProvisioningUpdates` разрешает Xcode менять provisioning resources;
применяй его только при согласованной автоматической подписи. Флаг не создаёт
авторизацию сам по себе и не исправляет закрытый private key.

Сборочные daemon/worker-процессы иногда сохраняют контекст старой SSH-сессии.
Если это подтверждено, штатно перезапусти только соответствующий build server
в разблокированной сессии. Не удаляй кэш и не прерывай чужие сборки.

## 7. Собери архив и экспортируй IPA

Предпочитай скрипт проекта. Ниже запасной вариант для обычного Xcode-проекта,
запускаемый на сборщике после настройки контейнера и подписи выше:

```bash
set -euo pipefail

SCHEME='<shared scheme>'
CONFIGURATION='<archive configuration>'
BUILD_NUMBER='<agreed build number>'
CACHE_KEY='<project-and-toolchain-cache-key>'
EXPORT_OPTIONS='<absolute path to validated ExportOptions.plist>'

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-${BUILD_NUMBER}"
RUN_DIR="$REMOTE_REPO/build-artifacts/$RUN_ID"
DERIVED_DATA="$HOME/Library/Caches/remote-ios-build/$CACHE_KEY/DerivedData"
mkdir -p "$RUN_DIR"

xcodebuild "${CONTAINER_ARGS[@]}" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -archivePath "$RUN_DIR/Application.xcarchive" \
  -resultBundlePath "$RUN_DIR/Archive.xcresult" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive 2>&1 | tee "$RUN_DIR/archive.log"

xcodebuild -exportArchive \
  -archivePath "$RUN_DIR/Application.xcarchive" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$RUN_DIR/export" \
  2>&1 | tee "$RUN_DIR/export.log"
```

`CURRENT_PROJECT_VERSION` действует, если проект использует эту настройку для
`CFBundleVersion`. Проверь итоговое значение и совместимость версий расширений.
Не меняй marketing version или файлы проекта без необходимости.

Используй существующий проверенный `ExportOptions.plist` или файл из ручного
экспорта этого проекта в Xcode. Если его нет, создай под согласованный способ
распространения и подписи. Актуальные ключи и значения `method` смотри через
`xcodebuild -help` на выбранном Xcode, не копируй устаревшие значения вслепую.
Для manual export проверь mapping `provisioningProfiles` для всех app targets.
Если нужен только локальный экспорт, не включай загрузку в App Store Connect.

Не упаковывай неподписанный `.app` вручную и не называй результат готовым IPA.
`CODE_SIGNING_ALLOWED=NO` допустим для отдельной проверки компиляции, но не
подтверждает возможность установки и работу подписанного приложения.

При `tee` обязательно сохраняй exit status сборки через `pipefail`. Храни полный
лог и `.xcresult` внутри отдельного запуска, не перезаписывай прошлый результат.
Завершённый archive не означает успешный export или готовность к установке.

Тесты запускай штатным способом проекта на подходящем simulator/device. Для
`xcodebuild test` сначала установи доступный destination и нужный runtime.
Не выдавай simulator-тесты за проверку push, Face ID или других функций iPhone.

## 8. Проверь именно экспортированный результат

Экспорт может переподписывать приложение, поэтому проверки одного `.xcarchive`
недостаточно. Найди фактическое имя IPA, не угадывай его по названию scheme.

На сборщике, в Bash, после успешного export:

```bash
IPA='<absolute path to the exported IPA>'
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ios-ipa-verify.XXXXXX")"
ditto -x -k "$IPA" "$VERIFY_DIR"

APPS=("$VERIFY_DIR"/Payload/*.app)
test "${#APPS[@]}" -eq 1
APP="${APPS[0]}"
test -d "$APP"

/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP"

EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
xcrun dwarfdump --uuid "$APP/$EXECUTABLE"
shasum -a 256 "$IPA"
```

Также проверь embedded profiles, их срок действия, допустимые устройства и
фактические entitlements у приложения и каждого расширения. Не печатай целиком
профили с перечнями устройств в общий отчёт. Для push важен `aps-environment`,
для общих данных нужны согласованные app groups. Подпись не гарантирует, что
серверные push credentials и backend настроены правильно.

Сохрани соответствующие dSYMs из архива или штатного build output. Сравни UUID
исполняемых файлов с UUID их dSYMs, включая собственные динамические frameworks.
Не смешивай символы от разных сборок. `--deep` выше относится только к проверке:
не используй его для обходной переподписи всего приложения.

Проверяй подпись на сборщике с его настроенным trust/keychain. Если второй Mac
сообщает об отсутствии доверия, отдели проблему локального trust от повреждения
пакета; не меняй доверие глобально ради зелёной проверки.

## 9. Верни артефакты и при необходимости установи

Передай на локальный компьютер IPA, соответствующие dSYMs, build/export logs
и краткий отчёт о сборке. Большой `.xcarchive`/`.xcresult` можно оставить на
сборщике, сообщив точные пути. Не публикуй их в стороннем сервисе без запроса.

Пример загрузки одного файла из локального Bash:

```bash
LOCAL_RUN_DIR='<absolute local artifact directory for this run>'
REMOTE_IPA='<absolute remote IPA path>'
mkdir -p "$LOCAL_RUN_DIR"
scp "$BUILD_HOST:$REMOTE_IPA" "$LOCAL_RUN_DIR/"
```

Современный `scp` использует SFTP; при старом SCP или нестандартных именах проверь
экранирование remote path. После переноса вычисли SHA-256 локальной копии и
сравни с суммой на сборщике. Файл с подходящим именем или свежим mtime ещё не
доказывает, что это нужная сборка.

Устанавливай только по запросу и с компьютера, к которому подключён iPhone.
Он должен быть разблокирован и доверять этому Mac. Developer Mode включается,
если требуется выбранным способом установки. Убедись, что выбран нужный UDID.

- С полным Xcode проверь `xcrun devicectl help device install app`: обычно
  устанавливается распакованный подписанный `.app`, а не IPA напрямую.
- С `ideviceinstaller` сначала проверь его `--help`. Для версий с подкомандами
  используется `ideviceinstaller -u '<UDID>' install '<absolute IPA path>'`.
- Simulator `.app` нельзя установить на iPhone. IPA для App Store/TestFlight
  нельзя считать пакетом для обычной прямой установки на произвольное устройство.
- Для обновления не удаляй старое приложение. Проверь Bundle ID, Team и
  совместимость подписи/entitlements. Не обещай сохранность данных при смене
  этих параметров и не используй переустановку как автоматическое исправление.

## 10. Если что-то сломалось

| Симптом | Что проверять сначала |
| --- | --- |
| SSH timeout / refused | адрес, VPN/сеть, Remote Login, SSH alias, доступный порт |
| Permission denied (publickey) | правильный пользователь и настроенный ключ; не пытайся добывать чужие credentials |
| `xcodebuild` требует Xcode | полный Xcode и `DEVELOPER_DIR`, а не только Command Line Tools |
| Scheme не найдена | контейнер, shared scheme, генерация проекта, синхронизация |
| SDK/runtime недоступен | выбранный Xcode, platform support, `xcrun simctl list runtimes` |
| `actool`: нет simulator runtimes при device build | доступные runtimes выбранного Xcode; не вырезай ресурсы ради обхода ошибки |
| Зависимость не скачивается | lock-файл, доступ к private registry/repo, proxy; не отключай TLS |
| `errSecInternalComponent` / interaction not allowed | unlock и signing probe в той же SSH-сессии, private key ACL, доступ build worker |
| Identity есть, подписи нет | наличие private key, правильный keychain, trust chain и срок сертификата |
| No matching provisioning profile | Team, Bundle ID, режим подписи, profiles для extensions и UDID |
| Entitlement not supported | capability в Apple Developer и профиле; правка plist сама право не выдаёт |
| Archive успешен, export нет | ExportOptions, способ распространения, distribution identity и mapping профилей |
| Сборка старая | hardcoded build number, неправильный output directory, фактический `CFBundleVersion` |
| Установка не идёт | устройство/trust/Developer Mode, UDID в профиле, подпись, iOS version, свободное место |
| Устройство не видно локально | проверь, не подключено ли оно к другому Mac; SSH не пробрасывает USB автоматически |

При проблеме с ACL не применяй `set-key-partition-list` ко всем ключам. Сначала
определи нужный private key и согласуй узкое изменение. Не путай имя сертификата
с label private key. Если временно меняется keychain search list, сохраняй и
восстанавливай её, исключи одновременные signing jobs. Забытый пароль keychain
не восстанавливается пересборкой и не оправдывает её удаление.

Ошибка подключения к серверу push, backend или API не исправляется очисткой
кэша или повторной подписью. Разделяй компиляцию, подпись, установку и runtime.
Проверяй работоспособность инструмента чтения логов, прежде чем считать пустой
вывод доказательством отсутствия события.

## 11. Что сообщить пользователю

Коротко укажи:

1. Что именно собрано: версия/build number, Bundle ID, схема/конфигурация.
2. На каком Mac и каким Xcode, из какой ревизии и с какими локальными правками.
3. Абсолютные пути к IPA и dSYMs на локальном компьютере и сборщике.
4. Результаты проверки подписи, UUID/dSYMs и совпадения SHA-256 после переноса.
5. Какие тесты выполнены, что не проверялось на реальном устройстве.
6. Установлено ли приложение; если нет, точную команду под доступный инструмент.
7. Если задача остановилась: конкретный этап, ошибка и одно нужное действие.

Не называй «готово» ситуацию, где скомпилировался код, но не прошли подпись,
export или перенос. Не утверждай, что исправлена функция приложения, только
потому что сборка и установка завершились успешно.

После первого успешного запуска зафиксируй параметры и проверенную команду
в отдельном документе конкретного проекта. Этот универсальный шаблон оставь
без реальных адресов, signing identities и секретов.

## Справочники

Параметры установленного toolchain проверяй локально: `xcodebuild -help`,
`man xcodebuild`, `xcrun devicectl help`, `security help`.

- [Apple: Xcode command-line tools](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference)
- [Apple: command-line build and archive FAQ](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
- [Apple: archive export files и ExportOptions](https://help.apple.com/xcode/mac/current/en.lproj/deva1f2ab5a2.html)
- [Apple: distribution to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Apple: manual signing](https://help.apple.com/xcode/mac/current/en.lproj/dev1bf96f17e.html)
