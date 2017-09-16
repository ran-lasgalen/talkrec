# Папка для складывания файлов в очередь
set ::config(workdir) ~/talks

# Номер гарнитуры, обязательный
# set ::config(headset) 1

# Идентификатор салона в системе. Может быть передан из управляющей программы
# set ::config(siteId) 2

# Слушать команды на этом порту TCP 
set ::config(port) 17119

# Звуковая система. Известные: pulse, fake
set ::config(soundSystem) pulse

# Для pulse: регулярное выражение для поиска устройства
set ::config(deviceRE) input.usb-GN_Netcom_A_S_Jabra_PRO_9460

# Для fake: файл-источник записи
# set ::config(fakeRecord) "test-record.wav"
