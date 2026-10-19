# Issue 70: production Mosh+

Дата: 19.10.2026. База: main, c31195f2e753a1d8792a326e8f7c65341e1ba2be,
релиз 0.23.0. Продуктовые решения согласованы в интервью.
Технические решения ниже предложены для реализации; код и контракты пока
не изменены. Этот документ не является отчётом о mainnet-приёмке.

Связано: [issue 70](https://github.com/redstone-md/mosh-flutter/issues/70),
[действующий devnet-протокол](../Features/plus-devnet.md),
[ADR 0046](../ADR/0046-plus-devnet-blind-entitlements.md).
Devnet-пилот завершён 18.10.2026. Повторный пилот на 20 участников исключён.

## Согласованный продукт

| Область | Решение |
| --- | --- |
| Покупка | Поддержка разработки Mosh и проверяемый бейдж Mosh+ |
| Период | 30 дней, один платёж внешним кошельком, без автосписаний |
| USDC | 5 USDC, Solana mainnet |
| CLXAI | 2 575 CLXAI, фиксированная стартовая цена; ориентир скидки 30% |
| Изменение цены | Вручную, только для новых заказов; существующая цена неизменна |
| Казна | Squads 2 из 3; получатель — vault, не multisig configuration account |
| Устройства | Купленный статус доступен всем связанным устройствам аккаунта |
| Видимость | Один переключатель на аккаунт, изначально выключен |
| Продление | Заранее добавляет 30 дней после оплаченного срока; после истечения начинается с оплаты |
| Восстановление | Подтверждение кошельком возвращает его оплаченные периоды на новый аккаунт |
| Ограничение | Один дополнительный перевыпуск по каждой оплаченной покупке; повторы идемпотентны |
| Старый сертификат | Сохраняет действительность до исходного окончания; мгновенного отзыва нет |
| Недоплата | Не активирует PLUS; отдельные недоплаты не складываются |
| Переплата | Активирует обычный период без дополнительного срока |
| Споры и возвраты | Ручная обработка; автоматического распоряжения средствами нет |
| Проверка | Локальная подпись, срок и владение аккаунтом; billing для показа не нужен |
| Выпуск | Обычные Windows/macOS-сборки, после приёмки новых production-возможностей |

Кошелёк восстанавливает только собственные платежи. Оплата QR другого человека
оставляет возможность восстановления у плательщика. Чаты, ключи и идентичность
потерянного аккаунта таким восстановлением не возвращаются. Перенос сертификата
между связанными устройствами того же аккаунта не расходует перевыпуск.
Relay, mailbox, хранилище, имена, перевод сообщений и iPhone в этот слайс не входят.

## Что уже есть и что меняется

| Текущая граница | Изменение |
| --- | --- |
| [plus_catalog.dart](../../lib/src/features/plus/plus_catalog.dart) и [types.rs](../../mosh-core/src/plus/types.rs) | Вместо одного devnet-токена: выбранный asset, сеть, mint и собственные decimals |
| [purchase.rs](../../mosh-core/src/plus/purchase.rs) | Вместо одного order/prepared/certificate: независимые заказы и коллекция периодов |
| [certificate.rs](../../mosh-core/src/plus/certificate.rs) | Production domain и подписанные начало/конец периода |
| [protocol.rs](../../mosh-core/src/plus/protocol.rs), [peers.rs](../../mosh-core/src/plus/peers.rs) | Версия production-доказательства; видимость отделена от сертификатов |
| [device-link metadata](../../mosh-core/src/device_link/names_wire.rs) | Собственные PLUS-сообщения через существующий аутентифицированный transport |
| [plus_billing.dart](../../lib/src/features/plus/plus_billing.dart) | Выбор валюты, продление и сессия восстановления |
| [release.yml](../../.github/workflows/release.yml) и platform builders | Production-конфигурация обычных установщиков и правильные имена артефактов |

Сохраняем Riverpod, общий UserPlusBadge, native PLUS owner, encrypted redb,
Moss/MLS-доставку и частично слепую подпись. Не меняем Moss, историю чатов
и базовые бесплатные возможности. Сервер продолжает жить в отдельном закрытом
mosh-billing; его исходники, ключи и база не попадают в публичный репозиторий.
При подготовке этого плана закрытый репозиторий не читался и не изменялся.

## Деньги и проверка перевода

| Asset | Mainnet mint | Decimals | Сумма в минимальных единицах |
| --- | --- | --- | --- |
| USDC | EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v | 6 | 5000000 |
| CLXAI | ECZV4aRyQKz2zr3ZFB9qeb4EzJbzuMCQZ2gpiBQfoHrK | 9 | 2575000000000 |

Native и billing используют целые u64/bigint с проверкой переполнения.
Числа на HTTP передаются каноническими десятичными строками. Никаких float
для сумм или автоматического курса DEX. CLXAI mint проверен через mainnet RPC:
classic SPL, 9 decimals, mint/freeze authority отсутствуют. Перед запуском
повторяем проверку обоих mint, genesis сети и token accounts казны.

Каталог возвращает версию, product, network, recipient, обе валюты и prices.
Заказ фиксирует выбранную валюту, mint, decimals, целую сумму, reference,
получателя и версию условий. Native независимо проверяет quote и Solana Pay URI.
Проверяются finalized, успешная транзакция, правильный token program, mint,
получатель, reference и фактически полученное количество. Один перевод
долговечно принадлежит одному заказу. Callback, tx signature и подпись входа
не заменяют проверку оплаты. Продолжаем принимать поздний корректный платёж
по сохранённым условиям; старый QR нельзя молча переоценить.

Для восстановления сохраняем доказанный source token owner. Fee payer,
delegate и получатель не подменяют владельца списанных токенов. Поддерживаем
однозначный обычный SPL-перевод из подписывающего личного кошелька.
Неоднозначные источники, custodial/PDA-плательщики и несколько конкурирующих
полных платежей направляются в ручное разбирательство; чужой перевод не даёт
автоматического права на восстановление. Совместимость оплаты на Squads PDA
и заранее подготовленные ATA доказываются реальной приёмкой обоих asset.

## Продление с сохранением приватности

1. Billing хранит случайную renewal series и её paid-through. Секрет управления
   передаётся только связанным устройствам по защищённому account transport.
   Это приватный billing handle, не account_id, Moss ID, MLS key или wallet.
2. Все обычные продления одного аккаунта используют эту series. В одной SQLite
   транзакции verified payment закрепляется за order, выделяется следующий
   интервал и продвигается paid-through. Опорное время — first durable verified_at,
   как в пилоте, а не block time перевода. Поздно обнаруженный перевод получает
   следующий интервал в порядке durable paid commits, не переставляет старые.
   verified_at и интервал неизменны при retry/restart; повтор не добавляет дни.
3. Первый период доступен после durable paid. Как в пилоте, окончание округляется
   вверх от verified_at + 30 дней до суток UTC: не менее 30 дней.
   Публичное начало — начало суток verified_at.
   Следующие периоды начинаются с предыдущего окончания и добавляют ровно
   30 дней. После разрыва применяем правило первого периода.
4. Native сохраняет несколько независимо проверяемых сертификатов. Будущий
   период не активирует бейдж раньше начала. Текущее покрытие и оплаченный
   будущий срок вычисляются по интервалам, включая возможные разрывы.
5. Восстановление сохраняет оригинальные интервалы выбранных заказов.
   Оно не переносит их на «сегодня», не создаёт новый месяц и не возвращает
   периоды, оплаченные другим кошельком.

Предлагаемые production claims: protocol_version, issuer_key_id, product,
valid_from_day, valid_until_day и скрытый account subject. Domain:
mosh-plus-mainnet-v1; product: mosh-plus-supporter-30d. Подписываем каноническую
кодировку всех полей существующей частично слепой схемой. Series, order,
wallet, точные timestamps оплаты и уникальный номер покупки не входят в
публичный сертификат. Публикуем общие TS → Rust → Go test vectors.

**Компромисс приватности:** billing сможет связать покупки внутри series и
их плательщиков между собой. Mosh-аккаунт по-прежнему скрыт от billing.
Это необходимо явно описать рядом с прежними ограничениями по timing/cohorts.

**Обязательная проверка до реализации checkout:** bootstrap должен выбрать
одну series для связанных устройств. Нельзя независимо создавать series
на каждом устройстве и затем объединять оплаченные пересекающиеся периоды.
Предлагаемый безопасный bootstrap: один согласованный initializer в account
metadata, durable-save подтверждения и общий handle до разрешения QR на sibling.
При незавершённой первичной синхронизации показываем ожидание и не принимаем
платёж. Правила initializer при offline/revoked/lost device доказываем отдельным
сценарием; если единственность не обеспечена, покупки блокируются до согласования.
В нормальном режиме после bootstrap offline siblings используют общий
server-serialized schedule и не ждут друг друга для каждого продления.

Восстановление на новый аккаунт не отдаёт ему управление чужой исходной series:
выдаёт только wallet-scoped права на выбранные интервалы. Для последующих
покупок нужна также scheduling-only нижняя граница из исходной series:
она резервирует уже оплаченные будущие даты, не выдавая сертификат или
управление периодами другого плательщика. При выделении новой покупки billing
проверяет эту границу атомарно; retry/import не увеличивают её повторно.
UI различает доступное покрытие и зарезервированный срок: невосстановленный
чужой период не становится активным PLUS и не продаётся заново как свободный.

Это второй обязательный gate до checkout: доказать сценарий «восстановлен A,
затем новая покупка, затем восстановлен B» с неизменными исходными интервалами.
Нельзя считать сумму длительностей покрытием при их пересечении. Если
scheduling-only boundary не решает обнаруженное пересечение, checkout остаётся
закрытым до определения правила, а кейс не маскируется объединением коллекций.
Такая связь раскрывает billing и границу резервирования между series,
но не Mosh account_id; это тоже входит в описание privacy tradeoff.

## Wallet recovery и идемпотентная выдача

Native сначала сохраняет ephemeral recovery key и независимый polling capability.
Показывается QR/ссылка на HTTPS-страницу своего billing. Страница работает
с Wallet Standard, запрашивает подпись сообщения, без seed или расходной authority.
Используем SIWS через signIn либо подпись точно того же канонического сообщения
через signMessage, с проверкой официальными Wallet Standard helpers.
Сервер хранит ожидаемый challenge, проверяет срок и одноразовое потребление
nonce, domain/URI/network, purpose и recovery session/destination.
Одна проверка криптоподписи не проверяет актуальность challenge.
Подпись только по адресу из запроса и повтор использованного nonce недопустимы.
Пользователь видит назначение переноса и сверяет код устройства.
Для мобильного входа предусматриваем кнопку открытия recovery страницы
в wallet browser: у Solflare есть официальный browse universal link.
Обычная камера телефона и Safari сами по себе не предоставляют wallet provider.

После подписи открываем только оплаченные этим wallet заказы с оставшимся
сроком, включая будущие интервалы. Выбор и подтверждение восстановления
связаны с этой сессией; браузер не получает Mosh account_id или blinding secret.
Mobile-wallet вход и возврат на страницу обязательно проверяются на устройстве.
Обычная оплата по QR не требует отдельной wallet-login подписи.

На каждый paid order есть два долговечных слота: original и recovery.
Каждый связывает ровно один валидный blinded request с фиксированными claims
и сохранённым ответом. Одинаковый retry возвращает тот же результат.

| Состояние | Действие при wallet recovery |
| --- | --- |
| Paid, original ещё не связан | Занять original; оградить старый bearer от выдачи другого запроса |
| Original связан/issued, даже если ответ потерялся | Использовать единственный recovery slot |
| Recovery уже связан с тем же запросом | Вернуть сохранённый результат без расхода нового слота |
| Recovery связан с другим запросом | Отказать в дополнительном перевыпуске; доступна поддержка |

Связывание, смена generation/capability и выдача сериализованы на сервере.
Гонка original/recovery не создаёт третьего сертификата. Новое устройство
сохраняет blinding state до запроса. Потеря этого состояния после использования
recovery slot не разрешает ещё один автоматический перевыпуск.
Старые настоящие сертификаты остаются валидны до исходного конца; это
согласованный компромисс для бейджа, не протокол допуска к будущему paid relay.

## Контракты и локальное состояние

| Граница | Предлагаемое изменение |
| --- | --- |
| HTTP v2 catalog/order | Выбор asset, immutable quote, series capability и idempotency key |
| HTTP v2 refresh/issue | Фиксированный интервал, original slot; bearer обязателен |
| HTTP v2 recovery sessions | Public pairing ID отдельно от desktop polling capability; challenge/verify/consent |
| HTTP v2 recovery orders/issue | Только wallet-scoped enumeration и one-per-order recovery slot |
| Native bridge | Typed catalog/order validation, подготовка/финализация периода, recovery session, sync status |
| Snapshot | Active coverage, paid-through, pending orders, next intervals, visibility, recoverability/error |
| Encrypted records | local-v2: collection заказов, prepared state, сертификатов, series и sync/version |
| Account sync | Versioned PLUS envelope, paging, durable ack, retry, active roster authorization |
| Peer proof v2 | Mainnet domain; независимые visibility version и текущий/следующий сертификаты |

v2 endpoints и claims документируются публично; SQL, issuer и verifier остаются
в закрытом billing. Новые bridge/schema/wire контракты требуют проверки этого
плана перед реализацией. Применяем additive migration, не переписываем историю.
local-v1, pending inverses и devnet certificates сохраняются в своей среде;
ничего из devnet не превращается в mainnet entitlement.

Для visibility используем логическую версию counter + writer, как у chat names.
Синхронизация коллекции сертификатов не переключает visibility и не расходует
recovery. Равная preference version с новым сертификатом не является конфликтом.
Низкая версия не может отменить более новое скрытие. Concurrent writes сходятся
детерминированно; offline device не может узнать изменение до подключения.
PLUS owner не захватывает device-link/conversation lock; существующий порядок
device-link/conversation → PLUS сохраняется.

Peer proof содержит только ограниченное необходимое доказательство активного
или следующего периода и авторизованную visibility. Legacy optional proofs
игнорируются без нарушения обычной переписки. 0.23.0 не показывает mainnet PLUS;
devnet proofs не принимаются production issuer/domain. Подделанный клиент
не может создать сертификат для собеседника без подписи issuer.

## Слои реализации

1. Зафиксировать v2 contracts, interval/series bootstrap и wallet source policy.
   Проверить приватный billing при реализации: этот план основан на публичном
   контракте, а не на предположении о его актуальном внутреннем SQL.
2. Получить работающий tracer USDC: quote → finalized transfer → один период →
   native certificate → общий badge в существующих чатах. Добавить CLXAI
   через тот же asset path, без второго checkout/verifier.
3. Добавить serialized renewal, queued intervals и authenticated account sync.
   Проверить конкурентную покупку, offline sibling и будущий linked device.
4. Добавить wallet recovery web flow и original/recovery slots. Восстановить
   оплаченные периоды на новом аккаунте без раскрытия account subject billing.
5. Провести полную приёмку новых функций и production build configuration.
   У обычных установщиков mainnet pin и HTTPS billing; devnet остаётся отдельной
   явной конфигурацией. Недоступный billing не убирает действующий бейдж.
6. Подготовить PR, инструкции, release notes и установщики; после разрешения
   владельца включить публичные покупки и выпустить обычный релиз.

В клиенте новые библиотеки не планируются. Для recovery страницы/серверной
проверки предлагаются официальные Wallet Standard packages, прежде всего
@solana/wallet-standard-util; точные packages/versions фиксируются при реализации.
Нового frontend framework или новой криптосхемы не вводим. Используем существующие
Hono, SQLite, Solana Pay/Kit/token packages и blind-RSA implementation.

## Проверки и критерии завершения

Bug fixes начинают с caller-visible regression. Для новых переходов состояния
проверяем результат на HTTP/native seam; widget tests проверяют UI-поведение.
Для самого плана тесты приложения не запускаются.

- Обе decimals и atomic amounts; неверные mint/network/recipient/reference,
  failure/unfinalized и underpaid не выдают сертификат. Overpayment не продлевает.
- Duplicate/parallel refresh/issue и restart до/после durable commit сохраняют
  один платёж, исходный интервал и единственный результат каждого слота.
- Два linked устройства покупают одновременно: интервалы последовательны;
  повторное наблюдение платежа, retry и sync не добавляют новый период.
- Bootstrap гонки, offline/revoked device, падение initializer и upgrade v1
  не допускают оплату при неоднозначной series.
- Future certificate не действует раньше срока; часы UTC и границы суток
  не сокращают первый период ниже 30 дней. Recovery не меняет исходные даты.
- Certificate/visibility sync работает после restart, reconnect и нового linking;
  отзыв устройства, чужой account и replay не дают доступ к метаданным.
- Поддельный, просроченный, чужой и devnet certificate не дают mainnet badge.
  Показ/скрытие проверяются в DM, группе, канале и user identity surfaces.
- Recovery: верный кошелёк, другой кошелёк, fee payer/delegate, replay/expired
  challenge, два параллельных запроса, lost original response и использованный slot.
  Один wallet не получает периоды другого; capabilities не попадают в URL/log.
- TS → Rust → Go vectors для новых claims; Rust build/fmt/tests/clippy, FRB
  regeneration/drift, Flutter analyze/tests/format, private billing typecheck/tests.
  Используем реальные зависимости и существующий Moss runner.
- Целевые показатели changed-code coverage: ≥80% lines, ≥70% branches,
  где инструмент их предоставляет; generated code не маскирует результат.
- Готовые Windows x64/macOS universal установщики, их SHA-256 и конфигурация
  проверены. Затем контрольные настоящие mainnet платежи обоих asset,
  продление, перенос на новое устройство и wallet recovery на новом аккаунте.
  До этого mainnet acceptance не отмечается выполненной.

## Границы запуска и оставшиеся риски

Сейчас разрешена подготовка плана. План не разрешает mainnet-транзакции,
развёртывание, перемещение средств казны или публикацию релиза.
Дальнейшая реализация включает согласование технических контрактов выше.

До открытых покупок нужны реальные значения: HTTPS domain/host, production RPC,
Squads vault и проверенные ATA обоих token, production issuer public pin,
секреты и резервная копия issuer/SQLite вне Git, контакт поддержки и получатель
платежей в условиях. Правовой трек и разрешение владельца на реальные деньги
из исходного документа остаются отдельной границей запуска; правовая оценка
этим планом не выполнялась. Реальные credentials/addresses не выдумываем.
Эти данные не мешают подготовить и проверить реализацию на отдельной среде.

Основные риски: series bootstrap и privacy linkage, согласованность интервалов
при восстановлении части кошельков, один recovery slot при повторной потере
данных, реальная mobile-wallet совместимость и приватная версия billing.
Ротация issuer должна сохранять доверие всем ещё действующим и будущим
оплаченным периодам; публичный key_id зарезервирован с первой версии.
Прекращение продажи при аварии останавливает новые заказы, сохраняя refresh,
issue/recovery оплаченного и локальную проверку уже выданного.

При реализации обновить feature guide, Architecture, GLOSSARY и новый ADR;
сохранить devnet guide как отчёт о завершённом пилоте.
Не меняем внешний HTML-план из соседнего каталога в этой задаче.

## Первичные источники

- [Circle: USDC mint](https://developers.circle.com/stablecoins/usdc-contract-addresses).
- [Solana Pay: transfer request](https://docs.solanapay.com/spec).
- [Wallet Standard: SIWS verification](https://github.com/anza-xyz/wallet-standard/blob/master/packages/core/util/src/signIn.ts).
- [Solflare: открыть страницу в wallet browser](https://docs.solflare.com/solflare/technical/deeplinks/other-methods/browse).
- [Squads: vault, account и threshold](https://docs.squads.so/main/navigating-your-squad/settings).
