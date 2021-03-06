# Выбор сервера распознавания

## Годные сервера

### Доступные

dict `::serverState`, key {IP port}, value

    {connect 1|0 lastConnectT Tc checking Ts errors N lastErrorT Te jobs {
        file1.wav Tst1 file2.wav Tst2
    }}

- `connect`: результат прошлой проверки соединения. Если ее еще не было
  — 0. Выставляется в 1 (и `lastConnectT` в `$now`) также по успешном
  завершении распознавания. Выставляется в 0, если нет соединения с сервером,
  но не в случае, когда соединение есть, а распознавание не работает.

- `lastConnectT`: время последнего обновления (не смены) `connect`.

- `checking`: время старта текущей проверки соединения. 0, если таковой сейчас
  нет.

- `errors`: количество _последовательных_ ошибок распознавания. Сбрасывается в
  0 при каждом успешном, увеличивается на 1 при каждом неудачном.

- `lastErrorT`: время последней ошибки распознавания.

- `jobs`: задачи, работающие сейчас. Ключ — имя распознаваемого файла,
  значение — момент старта распознавания.

Сервер считается доступным, если:

- есть в конфиге (оттуда и берется)
- connect = 1
- checking = 0 *или* $now - checking < $::yaCheckInterval(checkIsGood) (2 с)
  (т.е. проверка если идет, то недолго)
- errors < 2 *или* $now - lastErrorT > $::yaCheckInterval(error) (меньше 2
  ошибок _подряд_ или последняя была уже давно)

Проверялка соединения запускается, если

- сервер есть в конфиге
- checking = 0
- *или*
  - connect = 1 *и* $now - lastConnectT > $::yaCheckInterval(connectOk)
  - connect = 0 *и* $now - lastConnectT > $::yaCheckInterval(connectFail)

Диспетчер проверялок перед запуском чистит все сервера, которых нет в конфиге,
и у которых checking = 0.

### Незанятые

Для _доступных_ серверов вычисляется количество возможных потоков
`[dict get $::speechkits $server]` минус количество ныне висящих заданий
`[dict size [dict get $::serverState $server jobs]]`

Если `errors > 0` (т.е. в прошлый раз была ошибка), количество возможных
потоков для начала ограничивается 1.

В списке для выбора каждый из незанятых серверов представляется в упомянутом
количестве, выбор случайный равномерный.
