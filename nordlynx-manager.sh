#!/usr/bin/env bash
# ==============================================================================
#  NordLynx Manager  —  Multi-Location SOCKS5 Proxy Factory
#  https://github.com/sepehrwwe49/nordlynx
#
#  Runs one NordVPN container per country (NordLynx or OpenVPN), each exposing
#  its own SOCKS5 port for Marzban / Pasarguard outbounds and routing rules.
#
#  License: MIT
# ==============================================================================
set -uo pipefail

VERSION="2.2.0"
APP_NAME="NordLynx Manager"

# ------------------------------------------------------------------ paths ----
APP_DIR="/opt/nordlynx-manager"
BUILD_DIR="$APP_DIR/build"
CONF_FILE="$APP_DIR/config.env"
TOKEN_FILE="$APP_DIR/.token"          # legacy single-token file
TOKENS_FILE="$APP_DIR/tokens.tsv"     # vault: name<TAB>token
TG_CONF="$APP_DIR/telegram.env"
BOT_FILE="/usr/local/bin/nordlynx-bot.sh"
BOT_STATE="$APP_DIR/bot-state"
SRC_DIR="$APP_DIR/src"                # where the one-liner parks the real files
REPO_RAW="https://raw.githubusercontent.com/sepehrwwe49/nordlynx/main"
BACKUP_DIR="$APP_DIR/backups"
EXPORT_DIR="$APP_DIR/exports"
LOG_FILE="$APP_DIR/manager.log"
HEALER_FILE="/usr/local/bin/nordlynx-healer.sh"

IMAGE_NAME="nordlynx-proxy"
IMAGE_TAG="latest"
IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
LABEL_NS="nlm"

# ------------------------------------------------------- container defaults ---
DEF_TECH="NordLynx"        # NordLynx | OpenVPN
DEF_PROTO="UDP"            # UDP | TCP   (OpenVPN only — NordLynx is always UDP)
DEF_AUTOCONNECT="on"
DEF_LAN="on"
DEF_ANALYTICS="off"
DEF_INNER_PORT=1080
BIND_ADDR_DEFAULT="127.0.0.1"

UI_LANG="en"               # en | fi | fa | fa-raw | ru | zh

# ----------------------------------------------------------------- colors ----
if [[ -t 1 ]]; then
  R=$'\e[0m';  B=$'\e[1m';  D=$'\e[2m'
  RED=$'\e[38;5;203m';   GRN=$'\e[38;5;84m';    YLW=$'\e[38;5;221m'
  BLU=$'\e[38;5;75m';    MAG=$'\e[38;5;177m';   CYN=$'\e[38;5;87m'
  GRY=$'\e[38;5;245m';   WHT=$'\e[38;5;255m'
  C1=$'\e[38;5;39m'; C2=$'\e[38;5;44m'; C3=$'\e[38;5;49m'
  C4=$'\e[38;5;84m'; C5=$'\e[38;5;120m'
else
  R= B= D= RED= GRN= YLW= BLU= MAG= CYN= GRY= WHT= C1= C2= C3= C4= C5=
fi

W=72   # box inner width

# ==============================================================================
#  i18n — six rendering modes
#    en      English
#    fi      Finglish (Persian written in latin letters — always renders)
#    fa      Persian, pre-shaped (Arabic presentation forms, visual order)
#    fa-raw  Persian, logical order (only for bidi-aware terminals)
#    ru      Русский
#    zh      简体中文
# ==============================================================================
declare -A T_en T_fi T_fa T_fs T_ru T_zh

# ---- English -----------------------------------------------------------------
T_en[tagline]="Multi-Location SOCKS5 Proxy Factory"
T_en[menu]="MAIN MENU"
T_en[m_deps]="Install prerequisites (Docker, tun, tools)"
T_en[m_token]="Set / update NordVPN access token"
T_en[m_build]="Build the proxy image"
T_en[m_add]="Create a new location"
T_en[m_batch]="Quick setup — build the classic 5 locations"
T_en[m_settings]="Location settings (country, protocol, port, toggles)"
T_en[m_status]="Live status dashboard"
T_en[m_test]="Test all proxies (real exit IP + country)"
T_en[m_logs]="View a container's logs"
T_en[m_restart]="Restart / stop / start a location"
T_en[m_del]="Delete a location"
T_en[m_export]="Export Marzban / Pasarguard outbounds"
T_en[m_wg]="WireGuard tools (private key, .conf export)"
T_en[m_healer]="Auto-healer (watchdog cron)"
T_en[m_backup]="Backup / restore configuration"
T_en[m_defaults]="Defaults for new locations"
T_en[m_lang]="Language / Zaban / Язык / 语言"
T_en[m_quit]="Quit"
T_en[choose]="Select an option"
T_en[invalid]="Invalid choice."
T_en[press]="Press Enter to continue…"
T_en[yes_no]="[y/N]"
T_en[done]="Done."
T_en[cancelled]="Cancelled."
T_en[need_root]="This script must run as root (or with sudo)."
T_en[no_token]="No access token stored yet. Use menu option 2 first."
T_en[no_image]="Image not built yet. Use menu option 3 first."
T_en[no_loc]="No locations found yet."
T_en[tok_prompt]="Paste your NordVPN access token (input hidden)"
T_en[tok_how]="Nord Account → Services → NordVPN → Manual setup → Generate new token"
T_en[tok_saved]="Token saved to %s (permissions 600)."
T_en[tok_empty]="Empty token — nothing saved."
T_en[pick_country]="Pick a country"
T_en[custom_country]="Custom (type a NordVPN country name)"
T_en[port_prompt]="Host port for SOCKS5"
T_en[inner_port_prompt]="SOCKS5 port inside the container"
T_en[port_busy]="Port %s is already in use."
T_en[bind_prompt]="Bind address (127.0.0.1 = local only, 0.0.0.0 = public)"
T_en[bind_warn]="Binding to 0.0.0.0 exposes an OPEN SOCKS5 proxy to the internet. Firewall it."
T_en[creating]="Creating container %s → %s on port %s"
T_en[waiting_conn]="Waiting for VPN tunnel to come up"
T_en[timeout]="Timed out. Check the logs from the main menu."
T_en[confirm_del]="Delete container %s permanently?"
T_en[testing]="Probing exit IP through each proxy…"
T_en[pick_tech]="Connection protocol"
T_en[tech_lynx]="NordLynx — WireGuard based, fastest (UDP only)"
T_en[tech_ovpn]="OpenVPN — slower, works where WireGuard is blocked"
T_en[pick_proto]="Transport protocol (OpenVPN only)"
T_en[proto_note]="NordLynx always uses UDP — transport choice is ignored."
T_en[autoconnect]="Auto-connect on container start"
T_en[lan_disc]="LAN discovery"
T_en[analytics]="NordVPN analytics"
T_en[enabled]="enabled"
T_en[disabled]="disabled"
T_en[cur_settings]="Current settings"
T_en[edit_what]="What do you want to change?"
T_en[apply_note]="Applying changes recreates the container (same name and host port)."
T_en[applying]="Recreating container with the new settings"
T_en[wg_only_lynx]="This location runs OpenVPN — WireGuard keys only exist on NordLynx."
T_en[wg_secret]="A WireGuard private key is a full credential. Anyone holding it can use your VPN slot."
T_en[wg_saved]="Config written to %s"
T_en[defaults_title]="Defaults applied to every NEW location"
T_en[saved]="Saved."

# ---- Finglish ----------------------------------------------------------------
T_fi[tagline]="Karkhane-ye proxy SOCKS5 chand-location"
T_fi[menu]="MENU-ye ASLI"
T_fi[m_deps]="Nasb-e pishniazha (Docker, tun, abzarha)"
T_fi[m_token]="Sabt ya taghir-e access token-e Nord"
T_fi[m_build]="Sakht-e image-e proxy"
T_fi[m_add]="Sakht-e location-e jadid"
T_fi[m_batch]="Nasb-e sari — sakht-e 5 location-e classic"
T_fi[m_settings]="Tanzimat-e location (keshvar, protocol, port, kelidha)"
T_fi[m_status]="Dashboard-e vaziat-e zende"
T_fi[m_test]="Test-e hame proxy-ha (IP va keshvar-e vaghei)"
T_fi[m_logs]="Moshahede-ye log-e yek container"
T_fi[m_restart]="Restart / Stop / Start-e location"
T_fi[m_del]="Hazf-e location"
T_fi[m_export]="Khorooji-ye outbound-e Marzban / Pasarguard"
T_fi[m_wg]="Abzar-e WireGuard (private key, export-e .conf)"
T_fi[m_healer]="Tarmim-e khodkar (cron-e watchdog)"
T_fi[m_backup]="Backup / Restore-e tanzimat"
T_fi[m_defaults]="Pishfarz baraye location-haye jadid"
T_fi[m_lang]="Language / Zaban / Язык / 语言"
T_fi[m_quit]="Khorooj"
T_fi[choose]="Yek gozine ra entekhab kon"
T_fi[invalid]="Gozine-ye namotabar."
T_fi[press]="Baraye edame Enter bezan…"
T_fi[yes_no]="[y/N]"
T_fi[done]="Anjam shod."
T_fi[cancelled]="Laghv shod."
T_fi[need_root]="In script bayad ba root ya sudo ejra shavad."
T_fi[no_token]="Hanooz token zakhire nashode. Aval gozine 2 ra bezan."
T_fi[no_image]="Image sakhte nashode. Aval gozine 3 ra bezan."
T_fi[no_loc]="Hanooz hich location-i sakhte nashode."
T_fi[tok_prompt]="Access token-e Nord ra paste kon (voroodi makhfi ast)"
T_fi[tok_how]="Nord Account > Services > NordVPN > Manual setup > Generate new token"
T_fi[tok_saved]="Token dar %s zakhire shod (dastresi 600)."
T_fi[tok_empty]="Token khali bood — chizi zakhire nashod."
T_fi[pick_country]="Keshvar ra entekhab kon"
T_fi[custom_country]="Delkhah (esm-e keshvar dar Nord ra benevis)"
T_fi[port_prompt]="Port-e host baraye SOCKS5"
T_fi[inner_port_prompt]="Port-e SOCKS5 dakhel-e container"
T_fi[port_busy]="Port %s ghablan eshghal shode."
T_fi[bind_prompt]="Bind address (127.0.0.1 faghat local, 0.0.0.0 omoomi)"
T_fi[bind_warn]="Bind rooye 0.0.0.0 yani proxy SOCKS5-e baz rooye internet. Hatman firewall bezar."
T_fi[creating]="Sakht-e container %s -> %s rooye port %s"
T_fi[waiting_conn]="Dar entezar-e bala amadan-e tunnel-e VPN"
T_fi[timeout]="Zaman tamam shod. Log ra az menu-ye asli bebin."
T_fi[confirm_del]="Container %s baraye hamishe hazf shavad?"
T_fi[testing]="Dar hal-e test-e IP-e khorooji-ye har proxy…"
T_fi[pick_tech]="Protocol-e ettesal"
T_fi[tech_lynx]="NordLynx — bar paye WireGuard, sari-tarin (faghat UDP)"
T_fi[tech_ovpn]="OpenVPN — kondtar, vali jayi ke WireGuard block ast kar mikonad"
T_fi[pick_proto]="Protocol-e transport (faghat baraye OpenVPN)"
T_fi[proto_note]="NordLynx hamishe UDP ast — entekhab-e transport nadide gerefte mishavad."
T_fi[autoconnect]="Auto-connect hengam-e start-e container"
T_fi[lan_disc]="LAN discovery"
T_fi[analytics]="Analytics-e NordVPN"
T_fi[enabled]="faal"
T_fi[disabled]="gheyr-e faal"
T_fi[cur_settings]="Tanzimat-e feli"
T_fi[edit_what]="Che chizi ra mikhahi avaz koni?"
T_fi[apply_note]="Emal-e taghirat container ra dobare misazad (haman esm va haman port-e host)."
T_fi[applying]="Sakht-e dobare-ye container ba tanzimat-e jadid"
T_fi[wg_only_lynx]="In location OpenVPN ast — kelid-e WireGuard faghat rooye NordLynx vojood darad."
T_fi[wg_secret]="Private key-e WireGuard yek credential-e kamel ast. Har kas dashte bashad mitavanad estefade konad."
T_fi[wg_saved]="Config dar %s neveshte shod"
T_fi[defaults_title]="Pishfarz baraye hameye location-haye JADID"
T_fi[saved]="Zakhire shod."

# ---- Русский -----------------------------------------------------------------
T_ru[tagline]="Фабрика SOCKS5-прокси по странам"
T_ru[menu]="ГЛАВНОЕ МЕНЮ"
T_ru[m_deps]="Установить зависимости (Docker, tun, утилиты)"
T_ru[m_token]="Задать или обновить токен доступа NordVPN"
T_ru[m_build]="Собрать образ прокси"
T_ru[m_add]="Создать новую локацию"
T_ru[m_batch]="Быстрый старт — создать 5 классических локаций"
T_ru[m_settings]="Настройки локации (страна, протокол, порт, флаги)"
T_ru[m_status]="Панель состояния"
T_ru[m_test]="Проверить все прокси (реальный IP и страна)"
T_ru[m_logs]="Показать логи контейнера"
T_ru[m_restart]="Перезапуск / стоп / старт локации"
T_ru[m_del]="Удалить локацию"
T_ru[m_export]="Экспорт outbounds для Marzban / Pasarguard"
T_ru[m_wg]="Инструменты WireGuard (приватный ключ, .conf)"
T_ru[m_healer]="Автовосстановление (cron-сторож)"
T_ru[m_backup]="Резервная копия / восстановление"
T_ru[m_defaults]="Значения по умолчанию для новых локаций"
T_ru[m_lang]="Language / Zaban / Язык / 语言"
T_ru[m_quit]="Выход"
T_ru[choose]="Выберите пункт"
T_ru[invalid]="Неверный выбор."
T_ru[press]="Нажмите Enter для продолжения…"
T_ru[yes_no]="[y/N]"
T_ru[done]="Готово."
T_ru[cancelled]="Отменено."
T_ru[need_root]="Скрипт нужно запускать от root (или через sudo)."
T_ru[no_token]="Токен ещё не сохранён. Сначала пункт 2."
T_ru[no_image]="Образ ещё не собран. Сначала пункт 3."
T_ru[no_loc]="Локации пока не созданы."
T_ru[tok_prompt]="Вставьте токен доступа NordVPN (ввод скрыт)"
T_ru[tok_how]="Nord Account → Services → NordVPN → Manual setup → Generate new token"
T_ru[tok_saved]="Токен сохранён в %s (права 600)."
T_ru[tok_empty]="Пустой токен — ничего не сохранено."
T_ru[pick_country]="Выберите страну"
T_ru[custom_country]="Другая (введите название страны в NordVPN)"
T_ru[port_prompt]="Порт хоста для SOCKS5"
T_ru[inner_port_prompt]="Порт SOCKS5 внутри контейнера"
T_ru[port_busy]="Порт %s уже занят."
T_ru[bind_prompt]="Адрес привязки (127.0.0.1 — только локально, 0.0.0.0 — публично)"
T_ru[bind_warn]="Привязка к 0.0.0.0 открывает SOCKS5-прокси всему интернету. Закройте фаерволом."
T_ru[creating]="Создаётся контейнер %s → %s на порту %s"
T_ru[waiting_conn]="Ожидание поднятия VPN-туннеля"
T_ru[timeout]="Время вышло. Посмотрите логи из главного меню."
T_ru[confirm_del]="Удалить контейнер %s безвозвратно?"
T_ru[testing]="Проверка исходящего IP через каждый прокси…"
T_ru[pick_tech]="Протокол подключения"
T_ru[tech_lynx]="NordLynx — на базе WireGuard, самый быстрый (только UDP)"
T_ru[tech_ovpn]="OpenVPN — медленнее, работает там, где WireGuard заблокирован"
T_ru[pick_proto]="Транспортный протокол (только для OpenVPN)"
T_ru[proto_note]="NordLynx всегда использует UDP — выбор транспорта игнорируется."
T_ru[autoconnect]="Автоподключение при старте контейнера"
T_ru[lan_disc]="Обнаружение локальной сети"
T_ru[analytics]="Аналитика NordVPN"
T_ru[enabled]="включено"
T_ru[disabled]="выключено"
T_ru[cur_settings]="Текущие настройки"
T_ru[edit_what]="Что изменить?"
T_ru[apply_note]="Применение изменений пересоздаёт контейнер (имя и порт хоста сохраняются)."
T_ru[applying]="Пересоздание контейнера с новыми настройками"
T_ru[wg_only_lynx]="Эта локация на OpenVPN — ключи WireGuard есть только у NordLynx."
T_ru[wg_secret]="Приватный ключ WireGuard — это полноценные учётные данные. Храните его в тайне."
T_ru[wg_saved]="Конфиг записан в %s"
T_ru[defaults_title]="Значения по умолчанию для НОВЫХ локаций"
T_ru[saved]="Сохранено."

# ---- 简体中文 ------------------------------------------------------------------
T_zh[tagline]="多国家 SOCKS5 代理工厂"
T_zh[menu]="主菜单"
T_zh[m_deps]="安装依赖 (Docker、tun、工具)"
T_zh[m_token]="设置或更新 NordVPN 访问令牌"
T_zh[m_build]="构建代理镜像"
T_zh[m_add]="新建一个节点"
T_zh[m_batch]="快速部署 — 创建经典 5 个节点"
T_zh[m_settings]="节点设置 (国家、协议、端口、开关)"
T_zh[m_status]="实时状态面板"
T_zh[m_test]="测试所有代理 (真实出口 IP 与国家)"
T_zh[m_logs]="查看容器日志"
T_zh[m_restart]="重启 / 停止 / 启动节点"
T_zh[m_del]="删除节点"
T_zh[m_export]="导出 Marzban / Pasarguard 出站配置"
T_zh[m_wg]="WireGuard 工具 (私钥、.conf 导出)"
T_zh[m_healer]="自动修复 (cron 看门狗)"
T_zh[m_backup]="备份 / 恢复配置"
T_zh[m_defaults]="新节点的默认设置"
T_zh[m_lang]="Language / Zaban / Язык / 语言"
T_zh[m_quit]="退出"
T_zh[choose]="请选择一项"
T_zh[invalid]="无效的选择。"
T_zh[press]="按 Enter 继续…"
T_zh[yes_no]="[y/N]"
T_zh[done]="完成。"
T_zh[cancelled]="已取消。"
T_zh[need_root]="此脚本必须以 root (或 sudo) 运行。"
T_zh[no_token]="尚未保存令牌，请先使用菜单第 2 项。"
T_zh[no_image]="镜像尚未构建，请先使用菜单第 3 项。"
T_zh[no_loc]="还没有任何节点。"
T_zh[tok_prompt]="粘贴你的 NordVPN 访问令牌 (输入不显示)"
T_zh[tok_how]="Nord Account → Services → NordVPN → Manual setup → Generate new token"
T_zh[tok_saved]="令牌已保存到 %s (权限 600)。"
T_zh[tok_empty]="令牌为空 — 未保存。"
T_zh[pick_country]="选择国家"
T_zh[custom_country]="自定义 (输入 NordVPN 的国家名称)"
T_zh[port_prompt]="宿主机 SOCKS5 端口"
T_zh[inner_port_prompt]="容器内的 SOCKS5 端口"
T_zh[port_busy]="端口 %s 已被占用。"
T_zh[bind_prompt]="绑定地址 (127.0.0.1 仅本机，0.0.0.0 公开)"
T_zh[bind_warn]="绑定到 0.0.0.0 会把无认证的 SOCKS5 代理暴露到公网，请务必配置防火墙。"
T_zh[creating]="正在创建容器 %s → %s，端口 %s"
T_zh[waiting_conn]="等待 VPN 隧道建立"
T_zh[timeout]="超时。请从主菜单查看日志。"
T_zh[confirm_del]="永久删除容器 %s ?"
T_zh[testing]="正在通过每个代理探测出口 IP…"
T_zh[pick_tech]="连接协议"
T_zh[tech_lynx]="NordLynx — 基于 WireGuard，最快 (仅 UDP)"
T_zh[tech_ovpn]="OpenVPN — 较慢，但在 WireGuard 被封锁时可用"
T_zh[pick_proto]="传输协议 (仅 OpenVPN)"
T_zh[proto_note]="NordLynx 始终使用 UDP — 传输协议选择将被忽略。"
T_zh[autoconnect]="容器启动时自动连接"
T_zh[lan_disc]="局域网发现"
T_zh[analytics]="NordVPN 数据分析"
T_zh[enabled]="已启用"
T_zh[disabled]="已禁用"
T_zh[cur_settings]="当前设置"
T_zh[edit_what]="要修改哪一项？"
T_zh[apply_note]="应用更改会重建容器 (名称与宿主机端口保持不变)。"
T_zh[applying]="正在用新设置重建容器"
T_zh[wg_only_lynx]="该节点使用 OpenVPN — WireGuard 密钥仅存在于 NordLynx。"
T_zh[wg_secret]="WireGuard 私钥等同于完整凭据，任何人拿到都能使用你的 VPN。"
T_zh[wg_saved]="配置已写入 %s"
T_zh[defaults_title]="应用于所有新节点的默认值"
T_zh[saved]="已保存。"

# ---- فارسی (logical order) ---------------------------------------------------
T_fa[tagline]="کارخانه پروکسی SOCKS5 چند-لوکیشنه"
T_fa[menu]="منوی اصلی"
T_fa[m_deps]="نصب پیش‌نیازها (داکر، tun، ابزارها)"
T_fa[m_token]="ثبت یا تغییر اکسس‌توکن نورد"
T_fa[m_build]="ساخت ایمیج پروکسی"
T_fa[m_add]="ساخت لوکیشن جدید"
T_fa[m_batch]="نصب سریع — ساخت ۵ لوکیشن کلاسیک"
T_fa[m_settings]="تنظیمات لوکیشن (کشور، پروتکل، پورت، کلیدها)"
T_fa[m_status]="داشبورد وضعیت زنده"
T_fa[m_test]="تست همه پروکسی‌ها (آی‌پی و کشور واقعی)"
T_fa[m_logs]="مشاهده لاگ یک کانتینر"
T_fa[m_restart]="ری‌استارت / توقف / اجرای لوکیشن"
T_fa[m_del]="حذف لوکیشن"
T_fa[m_export]="خروجی اوتباند مرزبان / پاسارگارد"
T_fa[m_wg]="ابزار WireGuard (کلید خصوصی، خروجی conf.)"
T_fa[m_healer]="ترمیم خودکار (کران واچ‌داگ)"
T_fa[m_backup]="بکاپ / بازگردانی تنظیمات"
T_fa[m_defaults]="پیش‌فرض لوکیشن‌های جدید"
T_fa[m_lang]="Language / Zaban / Язык / 语言"
T_fa[m_quit]="خروج"
T_fa[choose]="یک گزینه را انتخاب کن"
T_fa[invalid]="گزینه نامعتبر."
T_fa[press]="برای ادامه Enter بزن…"
T_fa[yes_no]="[y/N]"
T_fa[done]="انجام شد."
T_fa[cancelled]="لغو شد."
T_fa[need_root]="این اسکریپت باید با root یا sudo اجرا شود."
T_fa[no_token]="هنوز توکنی ذخیره نشده. اول گزینه ۲ را بزن."
T_fa[no_image]="ایمیج ساخته نشده. اول گزینه ۳ را بزن."
T_fa[no_loc]="هنوز هیچ لوکیشنی ساخته نشده."
T_fa[tok_prompt]="اکسس‌توکن نورد را پیست کن (ورودی مخفی است)"
T_fa[tok_how]="Nord Account ← Services ← NordVPN ← Manual setup ← Generate new token"
T_fa[tok_saved]="توکن در %s ذخیره شد (دسترسی 600)."
T_fa[tok_empty]="توکن خالی بود — چیزی ذخیره نشد."
T_fa[pick_country]="کشور را انتخاب کن"
T_fa[custom_country]="دلخواه (نام کشور در نورد را بنویس)"
T_fa[port_prompt]="پورت هاست برای SOCKS5"
T_fa[inner_port_prompt]="پورت SOCKS5 داخل کانتینر"
T_fa[port_busy]="پورت %s قبلاً اشغال شده."
T_fa[bind_prompt]="آدرس Bind (127.0.0.1 فقط لوکال، 0.0.0.0 عمومی)"
T_fa[bind_warn]="بایند روی 0.0.0.0 یعنی پروکسی SOCKS5 باز روی اینترنت. حتماً فایروال بگذار."
T_fa[creating]="ساخت کانتینر %s → %s روی پورت %s"
T_fa[waiting_conn]="در انتظار بالا آمدن تونل VPN"
T_fa[timeout]="زمان تمام شد. لاگ را از منوی اصلی ببین."
T_fa[confirm_del]="کانتینر %s برای همیشه حذف شود؟"
T_fa[testing]="در حال تست آی‌پی خروجی هر پروکسی…"
T_fa[pick_tech]="پروتکل اتصال"
T_fa[tech_lynx]="NordLynx — بر پایه WireGuard، سریع‌ترین (فقط UDP)"
T_fa[tech_ovpn]="OpenVPN — کندتر، ولی جایی که WireGuard بسته است کار می‌کند"
T_fa[pick_proto]="پروتکل انتقال (فقط برای OpenVPN)"
T_fa[proto_note]="NordLynx همیشه UDP است — انتخاب انتقال نادیده گرفته می‌شود."
T_fa[autoconnect]="اتصال خودکار هنگام استارت کانتینر"
T_fa[lan_disc]="کشف شبکه محلی (LAN discovery)"
T_fa[analytics]="آنالیتیکس نورد"
T_fa[enabled]="فعال"
T_fa[disabled]="غیرفعال"
T_fa[cur_settings]="تنظیمات فعلی"
T_fa[edit_what]="چه چیزی را می‌خواهی عوض کنی؟"
T_fa[apply_note]="اعمال تغییرات کانتینر را دوباره می‌سازد (همان نام و همان پورت هاست)."
T_fa[applying]="ساخت دوباره کانتینر با تنظیمات جدید"
T_fa[wg_only_lynx]="این لوکیشن OpenVPN است — کلید WireGuard فقط روی NordLynx وجود دارد."
T_fa[wg_secret]="کلید خصوصی WireGuard یک credential کامل است. هرکس داشته باشد می‌تواند استفاده کند."
T_fa[wg_saved]="کانفیگ در %s نوشته شد"
T_fa[defaults_title]="پیش‌فرض همه لوکیشن‌های جدید"
T_fa[saved]="ذخیره شد."


# ---- short labels used by the settings editor --------------------------------
T_en[s_country]="Country";        T_en[s_tech]="Technology";     T_en[s_proto]="Transport"
T_en[s_hport]="Host port";        T_en[s_iport]="Container port";T_en[s_bind]="Bind address"
T_en[s_auto]="Auto-connect";      T_en[s_lan]="LAN discovery";   T_en[s_analytics]="Analytics"
T_fi[s_country]="Keshvar";        T_fi[s_tech]="Technology";     T_fi[s_proto]="Transport"
T_fi[s_hport]="Port-e host";      T_fi[s_iport]="Port-e container";T_fi[s_bind]="Bind address"
T_fi[s_auto]="Auto-connect";      T_fi[s_lan]="LAN discovery";   T_fi[s_analytics]="Analytics"
T_ru[s_country]="Страна";         T_ru[s_tech]="Технология";     T_ru[s_proto]="Транспорт"
T_ru[s_hport]="Порт хоста";       T_ru[s_iport]="Порт контейнера";T_ru[s_bind]="Адрес привязки"
T_ru[s_auto]="Автоподключение";   T_ru[s_lan]="Обнаружение LAN"; T_ru[s_analytics]="Аналитика"
T_zh[s_country]="国家";            T_zh[s_tech]="技术";            T_zh[s_proto]="传输协议"
T_zh[s_hport]="宿主机端口";         T_zh[s_iport]="容器端口";        T_zh[s_bind]="绑定地址"
T_zh[s_auto]="自动连接";           T_zh[s_lan]="局域网发现";        T_zh[s_analytics]="数据分析"
T_fa[s_country]="کشور";           T_fa[s_tech]="تکنولوژی";        T_fa[s_proto]="انتقال"
T_fa[s_hport]="پورت هاست";        T_fa[s_iport]="پورت کانتینر";    T_fa[s_bind]="آدرس Bind"
T_fa[s_auto]="اتصال خودکار";      T_fa[s_lan]="کشف شبکه محلی";     T_fa[s_analytics]="آنالیتیکس"

# ---- pre-shaped Persian (Arabic presentation forms, visual order) ------------
# Generated: terminals implement neither bidi nor Arabic shaping, so the text
# is pre-rendered here. Use the 'fa-raw' mode on terminals that do handle it.
T_fs[tagline]='ﻪﻨﺸﯿﮐﻮﻟ-ﺪﻨﭼ SOCKS5 ﯽﺴﮐﻭﺮﭘ ﻪﻧﺎﺧﺭﺎﮐ'
T_fs[menu]='ﯽﻠﺻﺍ ﯼﻮﻨﻣ'
T_fs[m_deps]='(ﺎﻫﺭﺍﺰﺑﺍ ،tun ،ﺮﮐﺍﺩ) ﺎﻫﺯﺎﯿﻧﺶﯿﭘ ﺐﺼﻧ'
T_fs[m_token]='ﺩﺭﻮﻧ ﻦﮐﻮﺗﺲﺴﮐﺍ ﺮﯿﯿﻐﺗ ﺎﯾ ﺖﺒﺛ'
T_fs[m_build]='ﯽﺴﮐﻭﺮﭘ ﺞﯿﻤﯾﺍ ﺖﺧﺎﺳ'
T_fs[m_add]='ﺪﯾﺪﺟ ﻦﺸﯿﮐﻮﻟ ﺖﺧﺎﺳ'
T_fs[m_batch]='ﮏﯿﺳﻼﮐ ﻦﺸﯿﮐﻮﻟ ۵ ﺖﺧﺎﺳ — ﻊﯾﺮﺳ ﺐﺼﻧ'
T_fs[m_settings]='(ﺎﻫﺪﯿﻠﮐ ،ﺕﺭﻮﭘ ،ﻞﮑﺗﻭﺮﭘ ،ﺭﻮﺸﮐ) ﻦﺸﯿﮐﻮﻟ ﺕﺎﻤﯿﻈﻨﺗ'
T_fs[m_status]='ﻩﺪﻧﺯ ﺖﯿﻌﺿﻭ ﺩﺭﻮﺒﺷﺍﺩ'
T_fs[m_test]='(ﯽﻌﻗﺍﻭ ﺭﻮﺸﮐ ﻭ ﯽﭘﯼﺁ) ﺎﻫﯽﺴﮐﻭﺮﭘ ﻪﻤﻫ ﺖﺴﺗ'
T_fs[m_logs]='ﺮﻨﯿﺘﻧﺎﮐ ﮏﯾ ﮒﻻ ﻩﺪﻫﺎﺸﻣ'
T_fs[m_restart]='ﻦﺸﯿﮐﻮﻟ ﯼﺍﺮﺟﺍ / ﻒﻗﻮﺗ / ﺕﺭﺎﺘﺳﺍﯼﺭ'
T_fs[m_del]='ﻦﺸﯿﮐﻮﻟ ﻑﺬﺣ'
T_fs[m_export]='ﺩﺭﺎﮔﺭﺎﺳﺎﭘ / ﻥﺎﺑﺯﺮﻣ ﺪﻧﺎﺒﺗﻭﺍ ﯽﺟﻭﺮﺧ'
T_fs[m_wg]='(.conf ﯽﺟﻭﺮﺧ ،ﯽﺻﻮﺼﺧ ﺪﯿﻠﮐ) WireGuard ﺭﺍﺰﺑﺍ'
T_fs[m_healer]='(ﮒﺍﺩﭺﺍﻭ ﻥﺍﺮﮐ) ﺭﺎﮐﺩﻮﺧ ﻢﯿﻣﺮﺗ'
T_fs[m_backup]='ﺕﺎﻤﯿﻈﻨﺗ ﯽﻧﺍﺩﺮﮔﺯﺎﺑ / ﭖﺎﮑﺑ'
T_fs[m_defaults]='ﺪﯾﺪﺟ ﯼﺎﻫﻦﺸﯿﮐﻮﻟ ﺽﺮﻓﺶﯿﭘ'
T_fs[m_lang]='Language / Zaban / Язык / 语言'
T_fs[m_quit]='ﺝﻭﺮﺧ'
T_fs[choose]='ﻦﮐ ﺏﺎﺨﺘﻧﺍ ﺍﺭ ﻪﻨﯾﺰﮔ ﮏﯾ'
T_fs[invalid]='.ﺮﺒﺘﻌﻣﺎﻧ ﻪﻨﯾﺰﮔ'
T_fs[press]='…ﻥﺰﺑ Enter ﻪﻣﺍﺩﺍ ﯼﺍﺮﺑ'
T_fs[yes_no]='[y/N]'
T_fs[done]='.ﺪﺷ ﻡﺎﺠﻧﺍ'
T_fs[cancelled]='.ﺪﺷ ﻮﻐﻟ'
T_fs[need_root]='.ﺩﻮﺷ ﺍﺮﺟﺍ sudo ﺎﯾ root ﺎﺑ ﺪﯾﺎﺑ ﺖﭙﯾﺮﮑﺳﺍ ﻦﯾﺍ'
T_fs[no_token]='.ﻥﺰﺑ ﺍﺭ ۲ ﻪﻨﯾﺰﮔ ﻝﻭﺍ .ﻩﺪﺸﻧ ﻩﺮﯿﺧﺫ ﯽﻨﮐﻮﺗ ﺯﻮﻨﻫ'
T_fs[no_image]='.ﻥﺰﺑ ﺍﺭ ۳ ﻪﻨﯾﺰﮔ ﻝﻭﺍ .ﻩﺪﺸﻧ ﻪﺘﺧﺎﺳ ﺞﯿﻤﯾﺍ'
T_fs[no_loc]='.ﻩﺪﺸﻧ ﻪﺘﺧﺎﺳ ﯽﻨﺸﯿﮐﻮﻟ ﭻﯿﻫ ﺯﻮﻨﻫ'
T_fs[tok_prompt]='(ﺖﺳﺍ ﯽﻔﺨﻣ ﯼﺩﻭﺭﻭ) ﻦﮐ ﺖﺴﯿﭘ ﺍﺭ ﺩﺭﻮﻧ ﻦﮐﻮﺗﺲﺴﮐﺍ'
T_fs[tok_how]='Nord Account ← Services ← NordVPN ← Manual setup ← Generate new token'
T_fs[tok_saved]='.(600 ﯽﺳﺮﺘﺳﺩ) ﺪﺷ ﻩﺮﯿﺧﺫ %1$s ﺭﺩ ﻦﮐﻮﺗ'
T_fs[tok_empty]='.ﺪﺸﻧ ﻩﺮﯿﺧﺫ ﯼﺰﯿﭼ — ﺩﻮﺑ ﯽﻟﺎﺧ ﻦﮐﻮﺗ'
T_fs[pick_country]='ﻦﮐ ﺏﺎﺨﺘﻧﺍ ﺍﺭ ﺭﻮﺸﮐ'
T_fs[custom_country]='(ﺲﯾﻮﻨﺑ ﺍﺭ ﺩﺭﻮﻧ ﺭﺩ ﺭﻮﺸﮐ ﻡﺎﻧ) ﻩﺍﻮﺨﻟﺩ'
T_fs[port_prompt]='SOCKS5 ﯼﺍﺮﺑ ﺖﺳﺎﻫ ﺕﺭﻮﭘ'
T_fs[inner_port_prompt]='ﺮﻨﯿﺘﻧﺎﮐ ﻞﺧﺍﺩ SOCKS5 ﺕﺭﻮﭘ'
T_fs[port_busy]='.ﻩﺪﺷ ﻝﺎﻐﺷﺍ ﻼﺒﻗ %1$s ﺕﺭﻮﭘ'
T_fs[bind_prompt]='(ﯽﻣﻮﻤﻋ 0.0.0.0 ،ﻝﺎﮐﻮﻟ ﻂﻘﻓ Bind (127.0.0.1 ﺱﺭﺩﺁ'
T_fs[bind_warn]='.ﺭﺍﺬﮕﺑ ﻝﺍﻭﺮﯾﺎﻓ ﺎﻤﺘﺣ .ﺖﻧﺮﺘﻨﯾﺍ ﯼﻭﺭ ﺯﺎﺑ SOCKS5 ﯽﺴﮐﻭﺮﭘ ﯽﻨﻌﯾ 0.0.0.0 ﯼﻭﺭ ﺪﻨﯾﺎﺑ'
T_fs[creating]='%3$s ﺕﺭﻮﭘ ﯼﻭﺭ %1$s → %2$s ﺮﻨﯿﺘﻧﺎﮐ ﺖﺧﺎﺳ'
T_fs[waiting_conn]='VPN ﻞﻧﻮﺗ ﻥﺪﻣﺁ ﻻﺎﺑ ﺭﺎﻈﺘﻧﺍ ﺭﺩ'
T_fs[timeout]='.ﻦﯿﺒﺑ ﯽﻠﺻﺍ ﯼﻮﻨﻣ ﺯﺍ ﺍﺭ ﮒﻻ .ﺪﺷ ﻡﺎﻤﺗ ﻥﺎﻣﺯ'
T_fs[confirm_del]='؟ﺩﻮﺷ ﻑﺬﺣ ﻪﺸﯿﻤﻫ ﯼﺍﺮﺑ %1$s ﺮﻨﯿﺘﻧﺎﮐ'
T_fs[testing]='…ﯽﺴﮐﻭﺮﭘ ﺮﻫ ﯽﺟﻭﺮﺧ ﯽﭘﯼﺁ ﺖﺴﺗ ﻝﺎﺣ ﺭﺩ'
T_fs[pick_tech]='ﻝﺎﺼﺗﺍ ﻞﮑﺗﻭﺮﭘ'
T_fs[tech_lynx]='NordLynx — ﻪﯾﺎﭘ ﺮﺑ WireGuard، ﻂﻘﻓ) ﻦﯾﺮﺗﻊﯾﺮﺳ UDP)'
T_fs[tech_ovpn]='OpenVPN — ﻪﮐ ﯽﯾﺎﺟ ﯽﻟﻭ ،ﺮﺗﺪﻨﮐ WireGuard ﺪﻨﮐﯽﻣ ﺭﺎﮐ ﺖﺳﺍ ﻪﺘﺴﺑ'
T_fs[pick_proto]='(OpenVPN ﯼﺍﺮﺑ ﻂﻘﻓ) ﻝﺎﻘﺘﻧﺍ ﻞﮑﺗﻭﺮﭘ'
T_fs[proto_note]='NordLynx ﻪﺸﯿﻤﻫ UDP ﺩﻮﺷﯽﻣ ﻪﺘﻓﺮﮔ ﻩﺪﯾﺩﺎﻧ ﻝﺎﻘﺘﻧﺍ ﺏﺎﺨﺘﻧﺍ — ﺖﺳﺍ.'
T_fs[autoconnect]='ﺮﻨﯿﺘﻧﺎﮐ ﺕﺭﺎﺘﺳﺍ ﻡﺎﮕﻨﻫ ﺭﺎﮐﺩﻮﺧ ﻝﺎﺼﺗﺍ'
T_fs[lan_disc]='(LAN discovery) ﯽﻠﺤﻣ ﻪﮑﺒﺷ ﻒﺸﮐ'
T_fs[analytics]='ﺩﺭﻮﻧ ﺲﮑﯿﺘﯿﻟﺎﻧﺁ'
T_fs[enabled]='ﻝﺎﻌﻓ'
T_fs[disabled]='ﻝﺎﻌﻓﺮﯿﻏ'
T_fs[cur_settings]='ﯽﻠﻌﻓ ﺕﺎﻤﯿﻈﻨﺗ'
T_fs[edit_what]='؟ﯽﻨﮐ ﺽﻮﻋ ﯽﻫﺍﻮﺧﯽﻣ ﺍﺭ ﯼﺰﯿﭼ ﻪﭼ'
T_fs[apply_note]='.(ﺖﺳﺎﻫ ﺕﺭﻮﭘ ﻥﺎﻤﻫ ﻭ ﻡﺎﻧ ﻥﺎﻤﻫ) ﺩﺯﺎﺳﯽﻣ ﻩﺭﺎﺑﻭﺩ ﺍﺭ ﺮﻨﯿﺘﻧﺎﮐ ﺕﺍﺮﯿﯿﻐﺗ ﻝﺎﻤﻋﺍ'
T_fs[applying]='ﺪﯾﺪﺟ ﺕﺎﻤﯿﻈﻨﺗ ﺎﺑ ﺮﻨﯿﺘﻧﺎﮐ ﻩﺭﺎﺑﻭﺩ ﺖﺧﺎﺳ'
T_fs[wg_only_lynx]='.ﺩﺭﺍﺩ ﺩﻮﺟﻭ NordLynx ﯼﻭﺭ ﻂﻘﻓ WireGuard ﺪﯿﻠﮐ — ﺖﺳﺍ OpenVPN ﻦﺸﯿﮐﻮﻟ ﻦﯾﺍ'
T_fs[wg_secret]='.ﺪﻨﮐ ﻩﺩﺎﻔﺘﺳﺍ ﺪﻧﺍﻮﺗﯽﻣ ﺪﺷﺎﺑ ﻪﺘﺷﺍﺩ ﺲﮐﺮﻫ .ﺖﺳﺍ ﻞﻣﺎﮐ credential ﮏﯾ WireGuard ﯽﺻﻮﺼﺧ ﺪﯿﻠﮐ'
T_fs[wg_saved]='ﺪﺷ ﻪﺘﺷﻮﻧ %1$s ﺭﺩ ﮓﯿﻔﻧﺎﮐ'
T_fs[defaults_title]='ﺪﯾﺪﺟ ﯼﺎﻫﻦﺸﯿﮐﻮﻟ ﻪﻤﻫ ﺽﺮﻓﺶﯿﭘ'
T_fs[saved]='.ﺪﺷ ﻩﺮﯿﺧﺫ'


T_fs[s_country]='ﺭﻮﺸﮐ'
T_fs[s_tech]='ﯼﮊﻮﻟﻮﻨﮑﺗ'
T_fs[s_proto]='ﻝﺎﻘﺘﻧﺍ'
T_fs[s_hport]='ﺖﺳﺎﻫ ﺕﺭﻮﭘ'
T_fs[s_iport]='ﺮﻨﯿﺘﻧﺎﮐ ﺕﺭﻮﭘ'
T_fs[s_bind]='Bind ﺱﺭﺩﺁ'
T_fs[s_auto]='ﺭﺎﮐﺩﻮﺧ ﻝﺎﺼﺗﺍ'
T_fs[s_lan]='ﯽﻠﺤﻣ ﻪﮑﺒﺷ ﻒﺸﮐ'
T_fs[s_analytics]='ﺲﮑﯿﺘﯿﻟﺎﻧﺁ'

# ---- v2.1: token vault, cities, telegram -------------------------------------
T_en[m_tokens]="Access tokens (add / remove / list)"
T_fi[m_tokens]="Access token-ha (afzoodan / hazf / list)"
T_ru[m_tokens]="Токены доступа (добавить / удалить / список)"
T_zh[m_tokens]="访问令牌 (添加 / 删除 / 列表)"
T_fa[m_tokens]="اکسس‌توکن‌ها (افزودن / حذف / لیست)"
T_fs[m_tokens]='(ﺖﺴﯿﻟ / ﻑﺬﺣ / ﻥﺩﻭﺰﻓﺍ) ﺎﻫﻦﮐﻮﺗﺲﺴﮐﺍ'
T_en[m_telegram]="Telegram bot (remote control)"
T_fi[m_telegram]="Bot-e Telegram (control az rah-e dur)"
T_ru[m_telegram]="Telegram-бот (удалённое управление)"
T_zh[m_telegram]="Telegram 机器人 (远程控制)"
T_fa[m_telegram]="ربات تلگرام (کنترل از راه دور)"
T_fs[m_telegram]='(ﺭﻭﺩ ﻩﺍﺭ ﺯﺍ ﻝﺮﺘﻨﮐ) ﻡﺍﺮﮕﻠﺗ ﺕﺎﺑﺭ'
T_en[no_tokens]="No access tokens stored yet — add one first."
T_fi[no_tokens]="Hich access token-i sabt nashode — aval yeki ezafe kon."
T_ru[no_tokens]="Токены не сохранены — сначала добавьте один."
T_zh[no_tokens]="尚未保存访问令牌 — 请先添加一个。"
T_fa[no_tokens]="هیچ اکسس‌توکنی ثبت نشده — اول یکی اضافه کن."
T_fs[no_tokens]='.ﻦﮐ ﻪﻓﺎﺿﺍ ﯽﮑﯾ ﻝﻭﺍ — ﻩﺪﺸﻧ ﺖﺒﺛ ﯽﻨﮐﻮﺗﺲﺴﮐﺍ ﭻﯿﻫ'
T_en[pick_token]="Pick an access token"
T_fi[pick_token]="Access token ra entekhab kon"
T_ru[pick_token]="Выберите токен доступа"
T_zh[pick_token]="选择访问令牌"
T_fa[pick_token]="اکسس‌توکن را انتخاب کن"
T_fs[pick_token]='ﻦﮐ ﺏﺎﺨﺘﻧﺍ ﺍﺭ ﻦﮐﻮﺗﺲﺴﮐﺍ'
T_en[pick_city]="Pick a city (optional)"
T_fi[pick_city]="Shahr ra entekhab kon (ekhtiari)"
T_ru[pick_city]="Выберите город (необязательно)"
T_zh[pick_city]="选择城市 (可选)"
T_fa[pick_city]="شهر را انتخاب کن (اختیاری)"
T_fs[pick_city]='(ﯼﺭﺎﯿﺘﺧﺍ) ﻦﮐ ﺏﺎﺨﺘﻧﺍ ﺍﺭ ﺮﻬﺷ'
T_en[city_any]="Any city — let NordVPN choose"
T_fi[city_any]="Har shahri — Nord khodesh entekhab konad"
T_ru[city_any]="Любой город — пусть выберет NordVPN"
T_zh[city_any]="任意城市 — 由 NordVPN 选择"
T_fa[city_any]="هر شهری — نورد خودش انتخاب کند"
T_fs[city_any]='ﺪﻨﮐ ﺏﺎﺨﺘﻧﺍ ﺵﺩﻮﺧ ﺩﺭﻮﻧ — ﯼﺮﻬﺷ ﺮﻫ'
T_en[s_token]="Token"
T_fi[s_token]="Token"
T_ru[s_token]="Токен"
T_zh[s_token]="令牌"
T_fa[s_token]="توکن"
T_fs[s_token]='ﻦﮐﻮﺗ'
T_en[s_city]="City"
T_fi[s_city]="Shahr"
T_ru[s_city]="Город"
T_zh[s_city]="城市"
T_fa[s_city]="شهر"
T_fs[s_city]='ﺮﻬﺷ'
T_en[tok_name_prompt]="A short name for this token (e.g. main, backup, client-a)"
T_fi[tok_name_prompt]="Yek esm-e kootah baraye in token (masalan main, backup)"
T_ru[tok_name_prompt]="Короткое имя для токена (например main, backup)"
T_zh[tok_name_prompt]="为该令牌取一个短名称 (例如 main、backup)"
T_fa[tok_name_prompt]="یک اسم کوتاه برای این توکن (مثلاً main یا backup)"
T_fs[tok_name_prompt]='(backup ﺎﯾ main ﻼﺜﻣ) ﻦﮐﻮﺗ ﻦﯾﺍ ﯼﺍﺮﺑ ﻩﺎﺗﻮﮐ ﻢﺳﺍ ﮏﯾ'
T_en[tok_added]="Token saved as '%s'."
T_fi[tok_added]="Token ba esm '%s' zakhire shod."
T_ru[tok_added]="Токен сохранён как «%s»."
T_zh[tok_added]="令牌已保存为 “%s”。"
T_fa[tok_added]="توکن با نام «%s» ذخیره شد."
T_fs[tok_added]='.ﺪﺷ ﻩﺮﯿﺧﺫ «%1$s» ﻡﺎﻧ ﺎﺑ ﻦﮐﻮﺗ'
T_en[tok_deleted]="Token '%s' removed."
T_fi[tok_deleted]="Token '%s' hazf shod."
T_ru[tok_deleted]="Токен «%s» удалён."
T_zh[tok_deleted]="令牌 “%s” 已删除。"
T_fa[tok_deleted]="توکن «%s» حذف شد."
T_fs[tok_deleted]='.ﺪﺷ ﻑﺬﺣ «%1$s» ﻦﮐﻮﺗ'

T_en[m_update]="Update from GitHub"
T_fi[m_update]="Update az GitHub"
T_ru[m_update]="Обновить с GitHub"
T_zh[m_update]="从 GitHub 更新"
T_fa[m_update]="آپدیت از گیت‌هاب"
T_fs[m_update]='ﺏﺎﻫﺖﯿﮔ ﺯﺍ ﺖﯾﺪﭘﺁ'

t() { local k="$1" v=""
  case "$UI_LANG" in
    fi)     v="${T_fi[$k]:-}" ;;
    fa)     v="${T_fs[$k]:-${T_fa[$k]:-}}" ;;
    fa-raw) v="${T_fa[$k]:-}" ;;
    ru)     v="${T_ru[$k]:-}" ;;
    zh)     v="${T_zh[$k]:-}" ;;
  esac
  [[ -z "$v" ]] && v="${T_en[$k]:-$k}"
  printf '%s' "$v"
}

lang_name() {
  case "${1:-$UI_LANG}" in
    en) printf 'English' ;;      fi) printf 'Finglish' ;;
    fa) printf 'Farsi (shaped)' ;; fa-raw) printf 'Farsi (raw)' ;;
    ru) printf 'Русский' ;;      zh) printf '简体中文' ;;
  esac
}

# ====================================================================== ui ====
strip_ansi() { printf '%s' "$1" | sed $'s/\e\\[[0-9;]*m//g'; }

# Terminal cell width: CJK and most emoji occupy two columns.
dispwidth() {
  local s; s="$(strip_ansi "$1")"
  local n=0 i ch code len=${#s}
  for (( i=0; i<len; i++ )); do
    ch="${s:i:1}"
    printf -v code '%d' "'$ch" 2>/dev/null || code=65
    if   (( code >= 0x1F1E6 && code <= 0x1F1FF )); then n=$(( n + 1 ))   # flag halves
    elif (( (code >= 0x1100  && code <= 0x115F)  ||
            (code >= 0x2E80  && code <= 0x303E)  ||
            (code >= 0x3041  && code <= 0x33FF)  ||
            (code >= 0x3400  && code <= 0x4DBF)  ||
            (code >= 0x4E00  && code <= 0x9FFF)  ||
            (code >= 0xA000  && code <= 0xA4CF)  ||
            (code >= 0xAC00  && code <= 0xD7A3)  ||
            (code >= 0xF900  && code <= 0xFAFF)  ||
            (code >= 0xFE30  && code <= 0xFE6F)  ||
            (code >= 0xFF00  && code <= 0xFF60)  ||
            (code >= 0xFFE0  && code <= 0xFFE6)  ||
            (code >= 0x1F300 && code <= 0x1FAFF) )); then n=$(( n + 2 ))
    else n=$(( n + 1 ))
    fi
  done
  printf '%s' "$n"
}
vislen() { dispwidth "$1"; }

hr()      { printf '%s╭%s╮%s\n' "$C1" "$(printf '─%.0s' $(seq 1 $W))" "$R"; }
hr_end()  { printf '%s╰%s╯%s\n' "$C1" "$(printf '─%.0s' $(seq 1 $W))" "$R"; }
hr_mid()  { printf '%s├%s┤%s\n' "$C1" "$(printf '─%.0s' $(seq 1 $W))" "$R"; }
rowc() {
  local text="$1" len left right
  len=$(dispwidth "$text")
  left=$(( (W - len) / 2 )); right=$(( W - len - left ))
  (( left < 0 )) && left=0; (( right < 0 )) && right=0
  printf '%s│%s%*s%s%*s%s│%s\n' "$C1" "$R" "$left" "" "$text" "$right" "" "$C1" "$R"
}

banner() {
  clear 2>/dev/null || printf '\033[2J\033[H'
  printf '\n'
  hr
  rowc "${B}${C2}╔╗╔╔═╗╦═╗╔╦╗  ╦  ╦ ╦╔╗╔═╗ ╦${R}"
  rowc "${B}${C3}║║║║ ║╠╦╝ ║║  ║  ╚╦╝║║║╔╩╦╝${R}"
  rowc "${B}${C4}╝╚╝╚═╝╩╚══╩╝  ╩═╝ ╩ ╝╚╝╩ ╚═${R}"
  rowc "${GRY}$(t tagline)${R}"
  hr_mid
  rowc "${D}v${VERSION}  •  NordLynx / OpenVPN  •  Marzban / Pasarguard${R}"
  hr_end
  printf '\n'
}

ok()   { printf '  %s✔%s %s\n' "$GRN" "$R" "$1"; }
bad()  { printf '  %s✘%s %s\n' "$RED" "$R" "$1"; }
warn() { printf '  %s▲%s %s\n' "$YLW" "$R" "$1"; }
info() { printf '  %s•%s %s\n' "$BLU" "$R" "$1"; }
step() { printf '\n  %s%s▸ %s%s\n' "$B" "$CYN" "$1" "$R"; }
title() {
  local len; len=$(dispwidth "$1")
  printf '\n  %s%s%s\n  %s%s%s\n' "$B$WHT" "$1" "$R" "$GRY" "$(printf '─%.0s' $(seq 1 "$len"))" "$R"
}

log() { mkdir -p "$APP_DIR"; printf '[%s] %s\n' "$(date '+%F %T')" "$1" >>"$LOG_FILE" 2>/dev/null; }
pause() { printf '\n  %s%s%s ' "$GRY" "$(t press)" "$R"; read -r _ || true; }

ask() {
  local p="$1" def="${2:-}" ans
  if [[ -n "$def" ]]; then
    printf '  %s?%s %s %s[%s]%s: ' "$MAG" "$R" "$p" "$GRY" "$def" "$R" >&2
  else
    printf '  %s?%s %s: ' "$MAG" "$R" "$p" >&2
  fi
  read -r ans || true
  printf '%s' "${ans:-$def}"
}

confirm() {
  local ans
  printf '  %s?%s %s %s%s%s ' "$YLW" "$R" "$1" "$GRY" "$(t yes_no)" "$R" >&2
  read -r ans || true
  [[ "$ans" =~ ^([yY]|[yY][eE][sS])$ ]]
}

spin_run() {
  local msg="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏') i=0 rc
  local tmp; tmp="$(mktemp)"
  ( "$@" >"$tmp" 2>&1 ) & local pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s%s%s %s ' "$CYN" "${frames[i]}" "$R" "$msg"
    i=$(( (i+1) % 10 )); sleep 0.08
  done
  wait "$pid"; rc=$?
  if (( rc == 0 )); then printf '\r  %s✔%s %s%*s\n' "$GRN" "$R" "$msg" 12 ""
  else printf '\r  %s✘%s %s%*s\n' "$RED" "$R" "$msg" 12 ""
       sed 's/^/      /' "$tmp" | tail -n 15
  fi
  rm -f "$tmp"; return $rc
}

bar() {
  local cur=$1 tot=$2 width=${3:-34} filled i out=""
  (( tot <= 0 )) && tot=1
  filled=$(( cur * width / tot )); (( filled > width )) && filled=$width
  for (( i=0; i<filled; i++ )); do out+="█"; done
  for (( i=filled; i<width; i++ )); do out+="░"; done
  printf '%s' "$out"
}

progress() {
  local cur=$1 tot=$2 lbl="$3" pct
  (( tot <= 0 )) && tot=1
  pct=$(( cur * 100 / tot ))
  printf '\r  %s%s%s %s%3d%%%s  %-44s' "$C3" "$(bar "$cur" "$tot")" "$R" "$B" "$pct" "$R" "$lbl"
}

menu_item() { printf '   %s%2s%s  %s\n' "$B$C3" "$1" "$R" "$2"; }

padr() {   # padr <text> <width> -> text padded to display width
  local len; len=$(dispwidth "$1"); local pad=$(( $2 - len )); (( pad < 0 )) && pad=0
  printf '%s%*s' "$1" "$pad" ""
}

on_off() { [[ "$1" == "on" ]] && printf '%s%s%s' "$GRN" "$(t enabled)" "$R" || printf '%s%s%s' "$GRY" "$(t disabled)" "$R"; }
toggle()  { [[ "$1" == "on" ]] && printf 'off' || printf 'on'; }

# ================================================================= helpers ====
need_root() {
  if [[ "$(id -u)" -ne 0 ]]; then banner; bad "$(t need_root)"; printf '\n'; exit 1; fi
}
have() { command -v "$1" >/dev/null 2>&1; }
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--' | tr -cd 'a-z0-9-'; }
# ---- access-token vault: name<TAB>token, mode 600 ---------------------------
tok_migrate() {   # import a pre-2.1 single token file once
  [[ -s "$TOKENS_FILE" ]] && return 0
  [[ -s "$TOKEN_FILE"  ]] || return 0
  mkdir -p "$APP_DIR"
  printf 'default\t%s\n' "$(cat "$TOKEN_FILE")" >"$TOKENS_FILE"
  chmod 600 "$TOKENS_FILE"
}
tok_list()  { tok_migrate; [[ -s "$TOKENS_FILE" ]] && grep -v '^[[:space:]]*$' "$TOKENS_FILE"; }
tok_names() { tok_list | cut -f1; }
tok_count() { tok_list | grep -c . ; }
tok_get()   { tok_list | awk -F'\t' -v n="$1" '$1==n {print $2; exit}'; }
tok_first() { tok_list | head -1 | cut -f1; }
tok_del() {             # tok_del <name>
  [[ -s "$TOKENS_FILE" ]] || return 0
  local tmp; tmp="$(mktemp)"
  awk -F'\t' -v n="$1" '$1!=n' "$TOKENS_FILE" >"$tmp"
  mv "$tmp" "$TOKENS_FILE"; chmod 600 "$TOKENS_FILE"
}
tok_add()   {           # tok_add <name> <token>
  mkdir -p "$APP_DIR"; touch "$TOKENS_FILE"; chmod 600 "$TOKENS_FILE"
  tok_del "$1"
  printf '%s\t%s\n' "$1" "$2" >>"$TOKENS_FILE"
}
tok_mask()  { local t="$1"; printf '%s…%s' "${t:0:6}" "${t: -4}"; }
token_ok()  { [[ "$(tok_count)" -gt 0 ]]; }
token_get() { local n="${1:-}"; [[ -z "$n" ]] && n="$(tok_first)"; tok_get "$n"; }

pick_token() {          # echoes the chosen token NAME
  local -a names=(); mapfile -t names < <(tok_names)
  if (( ${#names[@]} == 0 )); then bad "$(t no_tokens)" >&2; return 1; fi
  if (( ${#names[@]} == 1 )); then printf '%s' "${names[0]}"; return 0; fi
  title "$(t pick_token)" >&2
  printf '\n' >&2
  local i
  for i in "${!names[@]}"; do
    printf '   %s%2d%s  %-24s %s%s%s\n' "$B$C3" $(( i + 1 )) "$R" "${names[$i]}" \
      "$GRY" "$(tok_mask "$(tok_get "${names[$i]}")")" "$R" >&2
  done
  printf '\n' >&2
  local sel; sel="$(ask "$(t choose)" "1")"
  [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#names[@]} )) || { bad "$(t invalid)" >&2; return 1; }
  printf '%s' "${names[$(( sel - 1 ))]}"
}
image_exists() { docker image inspect "$IMAGE" >/dev/null 2>&1; }

port_in_use() {
  local p="$1"
  if have ss; then ss -lntH "sport = :$p" 2>/dev/null | grep -q . && return 0; fi
  docker ps -a --format '{{.Ports}}' 2>/dev/null | grep -qE "(^|[^0-9])$p->" && return 0
  return 1
}

lbl() { printf '{{.Label "%s.%s"}}' "$LABEL_NS" "$1"; }

list_locations() {
  docker ps -a --filter "label=${LABEL_NS}.managed=1" \
    --format "{{.Names}}\t$(lbl country)\t$(lbl port)\t$(lbl bind)\t{{.State}}\t$(lbl tech)\t$(lbl proto)\t$(lbl iport)\t$(lbl token)\t$(lbl city)" \
    2>/dev/null | sort -t$'\t' -k3,3n
}
loc_count() { list_locations | grep -c . ; }

next_free_port() { local p=1081; while port_in_use "$p"; do p=$(( p + 1 )); done; printf '%s' "$p"; }

pick_location() {
  local -a names=() rows=()
  local n c p b s tech proto ip tokn city i=0
  while IFS=$'\t' read -r n c p b s tech proto ip tokn city; do
    [[ -z "$n" ]] && continue
    names+=("$n"); rows+=("$n|$c|$p|$s|$tech")
  done < <(list_locations)
  if (( ${#names[@]} == 0 )); then bad "$(t no_loc)" >&2; return 1; fi
  printf '\n' >&2
  for i in "${!rows[@]}"; do
    IFS='|' read -r n c p s tech <<<"${rows[$i]}"
    local dot="$RED●$R"; [[ "$s" == "running" ]] && dot="$GRN●$R"
    printf '   %s%2d%s  %s %-22s %s%-22s%s %s%-5s%s %s%s%s\n' \
      "$B$C3" $(( i + 1 )) "$R" "$dot" "$n" "$GRY" "$c" "$R" "$B" "$p" "$R" "$D" "${tech:-?}" "$R" >&2
  done
  printf '\n' >&2
  local sel; sel="$(ask "$(t choose)" "1")"
  [[ "$sel" =~ ^[0-9]+$ ]] || { bad "$(t invalid)" >&2; return 1; }
  (( sel >= 1 && sel <= ${#names[@]} )) || { bad "$(t invalid)" >&2; return 1; }
  printf '%s' "${names[$(( sel - 1 ))]}"
}

# =============================================================== countries ====
COUNTRIES=(
  "United_States|🇺🇸|United States"          "United_Kingdom|🇬🇧|United Kingdom"
  "Germany|🇩🇪|Germany"                      "Netherlands|🇳🇱|Netherlands"
  "France|🇫🇷|France"                        "Turkey|🇹🇷|Turkey"
  "United_Arab_Emirates|🇦🇪|UAE"             "Australia|🇦🇺|Australia"
  "Canada|🇨🇦|Canada"                        "Japan|🇯🇵|Japan"
  "Singapore|🇸🇬|Singapore"                  "Sweden|🇸🇪|Sweden"
  "Switzerland|🇨🇭|Switzerland"              "Italy|🇮🇹|Italy"
  "Spain|🇪🇸|Spain"                          "Poland|🇵🇱|Poland"
  "Finland|🇫🇮|Finland"                      "Norway|🇳🇴|Norway"
  "Romania|🇷🇴|Romania"                      "India|🇮🇳|India"
  "Brazil|🇧🇷|Brazil"                        "Hong_Kong|🇭🇰|Hong Kong"
  "South_Africa|🇿🇦|South Africa"            "Israel|🇮🇱|Israel"
  "Georgia|🇬🇪|Georgia"                      "Armenia|🇦🇲|Armenia"
  "Ukraine|🇺🇦|Ukraine"                      "Serbia|🇷🇸|Serbia"
  "Bulgaria|🇧🇬|Bulgaria"                    "Czech_Republic|🇨🇿|Czech Republic"
)

country_flag() {
  local want="$1" e code flag
  for e in "${COUNTRIES[@]}"; do
    IFS='|' read -r code flag _ <<<"$e"
    [[ "$code" == "$want" ]] && { printf '%s' "$flag"; return; }
  done
  printf '🌐'
}

pick_country() {
  local i=0 e code flag label
  title "$(t pick_country)" >&2
  printf '\n' >&2
  for e in "${COUNTRIES[@]}"; do
    IFS='|' read -r code flag label <<<"$e"
    i=$(( i + 1 ))
    printf '   %s%2d%s %s %-20s' "$B$C3" "$i" "$R" "$flag" "$label" >&2
    (( i % 2 == 0 )) && printf '\n' >&2
  done
  (( i % 2 != 0 )) && printf '\n' >&2
  printf '   %s%2d%s 🎯 %s\n\n' "$B$C3" $(( i + 1 )) "$R" "$(t custom_country)" >&2
  local sel; sel="$(ask "$(t choose)" "1")"
  if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#COUNTRIES[@]} )); then
    IFS='|' read -r code _ _ <<<"${COUNTRIES[$(( sel - 1 ))]}"
    printf '%s' "$code"
  elif [[ "$sel" == "$(( ${#COUNTRIES[@]} + 1 ))" ]]; then
    ask "Country name (use _ for spaces, e.g. Costa_Rica)" ""
  else
    return 1
  fi
}

pick_tech() {
  title "$(t pick_tech)" >&2
  printf '\n' >&2
  printf '   %s 1%s  %-12s %s%s%s\n'  "$B$C3" "$R" "NordLynx" "$GRY" "$(t tech_lynx)" "$R" >&2
  printf '   %s 2%s  %-12s %s%s%s\n\n' "$B$C3" "$R" "OpenVPN"  "$GRY" "$(t tech_ovpn)" "$R" >&2
  case "$(ask "$(t choose)" "1")" in
    2) printf 'OpenVPN' ;;
    *) printf 'NordLynx' ;;
  esac
}

pick_proto() {
  title "$(t pick_proto)" >&2
  printf '\n' >&2
  printf '   %s 1%s  UDP  %sfaster, default%s\n'      "$B$C3" "$R" "$GRY" "$R" >&2
  printf '   %s 2%s  TCP  %smore reliable on lossy or filtered links%s\n\n' "$B$C3" "$R" "$GRY" "$R" >&2
  case "$(ask "$(t choose)" "1")" in
    2) printf 'TCP' ;;
    *) printf 'UDP' ;;
  esac
}

# ============================================================ prerequisites ===
action_deps() {
  banner; title "1) $(t m_deps)"
  step "Package manager"
  if have apt-get; then ok "apt detected"; else bad "This installer targets Debian/Ubuntu."; pause; return; fi

  spin_run "apt-get update" apt-get update -qq
  spin_run "Installing base tools (curl, jq, iproute2, qrencode)" \
    env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      curl jq iproute2 ca-certificates gnupg lsb-release procps qrencode

  step "Docker"
  if have docker; then
    ok "docker $(docker --version | awk '{print $3}' | tr -d ,)"
  else
    spin_run "Installing Docker Engine (get.docker.com)" bash -c \
      'curl -fsSL https://get.docker.com -o /tmp/get-docker.sh && sh /tmp/get-docker.sh'
    have docker && ok "Docker installed" || bad "Docker install failed"
  fi
  systemctl enable --now docker >/dev/null 2>&1 || true
  docker info >/dev/null 2>&1 && ok "Docker daemon is running" || bad "Docker daemon not running"

  step "TUN device"
  modprobe tun 2>/dev/null || true
  if [[ -c /dev/net/tun ]]; then ok "/dev/net/tun present"
  else
    mkdir -p /dev/net && mknod /dev/net/tun c 10 200 && chmod 600 /dev/net/tun
    [[ -c /dev/net/tun ]] && ok "/dev/net/tun created" || bad "Could not create /dev/net/tun"
  fi
  grep -q '^tun$' /etc/modules 2>/dev/null || echo tun >>/etc/modules 2>/dev/null || true

  step "IPv4 forwarding"
  sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 && ok "net.ipv4.ip_forward=1"

  mkdir -p "$APP_DIR" "$BUILD_DIR" "$BACKUP_DIR" "$EXPORT_DIR"; chmod 700 "$APP_DIR"
  ok "Workdir: $APP_DIR"
  log "prerequisites installed"
  pause
}

# =================================================================== token ====
action_token() {
  while true; do
    banner; title "2) $(t m_tokens)"
    printf '\n  %s%s%s\n' "$GRY" "$(t tok_how)" "$R"
    local -a names=(); mapfile -t names < <(tok_names)
    printf '\n'
    if (( ${#names[@]} == 0 )); then
      warn "$(t no_tokens)"
    else
      printf '  %s%-4s %-24s %-18s %s%s\n' "$B$GRY" "#" "NAME" "TOKEN" "USED BY" "$R"
      printf '  %s%s%s\n' "$GRY" "$(printf '─%.0s' $(seq 1 66))" "$R"
      local i used
      for i in "${!names[@]}"; do
        used="$(list_locations | awk -F'\t' -v n="${names[$i]}" '$9==n' | wc -l)"
        printf '  %s%-4d%s %-24s %s%-18s%s %s\n' "$B$C3" $(( i + 1 )) "$R" "${names[$i]}" \
          "$GRY" "$(tok_mask "$(tok_get "${names[$i]}")")" "$R" "${used} location(s)"
      done
    fi
    printf '\n'
    menu_item 1 "Add a token"
    menu_item 2 "Remove a token"
    menu_item 3 "Show a token in full"
    printf '\n'; menu_item 0 "Back"; printf '\n'
    case "$(ask "$(t choose)" "0")" in
      1) local name tok
         name="$(ask "$(t tok_name_prompt)" "main")"
         name="$(printf '%s' "$name" | tr -cd 'A-Za-z0-9._-')"
         [[ -z "$name" ]] && { bad "$(t invalid)"; sleep 1; continue; }
         printf '  %s?%s %s: ' "$MAG" "$R" "$(t tok_prompt)"
         read -rs tok || true; printf '\n'
         tok="$(printf '%s' "$tok" | tr -d '[:space:]')"
         if [[ -z "$tok" ]]; then warn "$(t tok_empty)"; sleep 1; continue; fi
         tok_add "$name" "$tok"
         # shellcheck disable=SC2059
         printf "  ${GRN}✔${R} $(t tok_added)\n" "$name"
         warn "Never commit tokens to Git. Revoke leaked tokens in Nord Account."
         log "token added: $name"; sleep 2 ;;
      2) local n; n="$(pick_token)" || { sleep 1; continue; }
         local inuse; inuse="$(list_locations | awk -F'\t' -v x="$n" '$9==x {print $1}')"
         if [[ -n "$inuse" ]]; then
           warn "Still used by: $(tr '\n' ' ' <<<"$inuse")"
           confirm "Remove anyway? Those containers keep the token already baked in." || continue
         fi
         tok_del "$n"
         # shellcheck disable=SC2059
         printf "  ${GRN}✔${R} $(t tok_deleted)\n" "$n"
         log "token removed: $n"; sleep 2 ;;
      3) local n; n="$(pick_token)" || { sleep 1; continue; }
         printf '\n    %s%s%s\n' "$B$WHT" "$(tok_get "$n")" "$R"
         warn "Clear your screen when you are done."
         pause ;;
      0|"") return ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
  done
}

# ---- cities ------------------------------------------------------------------
# The city list comes from the NordVPN CLI, so it needs one running container.
cities_of() {   # cities_of <Country>
  local runner; runner="$(docker ps --filter "label=${LABEL_NS}.managed=1" --format '{{.Names}}' | head -1)"
  [[ -z "$runner" ]] && return 1
  docker exec "$runner" nordvpn cities "$1" 2>/dev/null \
    | tr ',' '\n' | sed 's/[[:space:]]*$//; s/^[[:space:]]*//' | grep -v '^$' | sort -u
}

pick_city() {   # pick_city <Country> — echoes a city name, or nothing for "any"
  local country="$1"
  local -a cities=(); mapfile -t cities < <(cities_of "$country" 2>/dev/null)
  (( ${#cities[@]} == 0 )) && return 0
  title "$(t pick_city)" >&2
  printf '\n   %s 0%s  %s\n' "$B$C3" "$R" "$(t city_any)" >&2
  local i
  for i in "${!cities[@]}"; do
    printf '   %s%2d%s  %s\n' "$B$C3" $(( i + 1 )) "$R" "${cities[$i]}" >&2
  done
  printf '\n' >&2
  local sel; sel="$(ask "$(t choose)" "0")"
  [[ "$sel" =~ ^[0-9]+$ ]] || return 0
  (( sel >= 1 && sel <= ${#cities[@]} )) && printf '%s' "${cities[$(( sel - 1 ))]}"
  return 0
}

# =================================================================== image ====
write_build_files() {
  mkdir -p "$BUILD_DIR"

  cat >"$BUILD_DIR/Dockerfile" <<'DOCKERFILE'
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl gnupg iproute2 iputils-ping procps \
        libcap2-bin sysvinit-utils net-tools \
        gcc make git libc6-dev \
        wireguard-tools iptables openvpn \
    && rm -rf /var/lib/apt/lists/*

# --- NordVPN CLI (official repo) ---------------------------------------------
RUN curl -fsSL https://repo.nordvpn.com/gpg/nordvpn_public.asc \
        | gpg --dearmor -o /usr/share/keyrings/nordvpn.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nordvpn.gpg] https://repo.nordvpn.com/deb/nordvpn/debian stable main" \
        > /etc/apt/sources.list.d/nordvpn.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends nordvpn \
    && rm -rf /var/lib/apt/lists/*

# --- microsocks (tiny SOCKS5 server) -----------------------------------------
RUN git clone --depth 1 https://github.com/rofl0r/microsocks /tmp/microsocks \
    && make -C /tmp/microsocks \
    && install -m 0755 /tmp/microsocks/microsocks /usr/local/bin/microsocks \
    && rm -rf /tmp/microsocks

# NORD_TOKEN is deliberately NOT declared here — it is passed at runtime only,
# so it never gets baked into an image layer.
ENV NORD_COUNTRY=United_States \
    NORD_CITY="" \
    NORD_TECH=NordLynx \
    NORD_PROTO=UDP \
    NORD_AUTOCONNECT=on \
    NORD_LAN=on \
    NORD_ANALYTICS=off \
    SOCKS_PORT=1080

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
DOCKERFILE

  cat >"$BUILD_DIR/entrypoint.sh" <<'ENTRYPOINT'
#!/usr/bin/env bash
# NordVPN proxy container entrypoint — 7 stages, fail loud.
set -uo pipefail

COUNTRY="${NORD_COUNTRY:-United_States}"
CITY="${NORD_CITY:-}"
TOKEN="${NORD_TOKEN:-}"
TECH="${NORD_TECH:-NordLynx}"          # NordLynx | OpenVPN
PROTO="${NORD_PROTO:-UDP}"             # UDP | TCP  (OpenVPN only)
AUTOCONNECT="${NORD_AUTOCONNECT:-on}"
LAN="${NORD_LAN:-on}"
ANALYTICS="${NORD_ANALYTICS:-off}"
PORT="${SOCKS_PORT:-1080}"
SOCK="/run/nordvpn/nordvpnd.sock"

say() { printf '\033[1;36m[%s]\033[0m %s\n' "$1" "$2"; }
die() { printf '\033[1;31m[FATAL]\033[0m %s\n' "$1"; exit 1; }

[ -n "$TOKEN" ] || die "NORD_TOKEN is empty."

say 1/7 "Starting NordVPN service…"
/etc/init.d/nordvpn start >/dev/null 2>&1 || true

say 2/7 "Waiting for NordVPN daemon socket…"
for i in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 1; done
[ -S "$SOCK" ] || die "Daemon socket never appeared: $SOCK"

say 3/7 "Logging in with access token…"
for i in 1 2 3; do
  nordvpn login --token "$TOKEN" 2>&1 | grep -qiE 'welcome|already logged' && break
  sleep 3
done
nordvpn account >/dev/null 2>&1 || die "Login failed — token invalid or expired."

say 4/7 "Applying settings: tech=${TECH} proto=${PROTO} lan=${LAN} analytics=${ANALYTICS}"
nordvpn set technology "$TECH" >/dev/null 2>&1 || die "Unsupported technology: $TECH"
if [ "$TECH" = "OpenVPN" ]; then
  nordvpn set protocol "$PROTO" >/dev/null 2>&1 || echo "      protocol $PROTO refused, keeping default"
else
  [ "$PROTO" = "TCP" ] && echo "      NordLynx is UDP-only — ignoring TCP request"
fi
nordvpn set analytics "$ANALYTICS"    >/dev/null 2>&1 || true
nordvpn set lan-discovery "$LAN"      >/dev/null 2>&1 || true
nordvpn allowlist add port "$PORT"    >/dev/null 2>&1 || \
  nordvpn whitelist add port "$PORT"  >/dev/null 2>&1 || true

say 5/7 "Auto-connect: ${AUTOCONNECT}"
if [ "$AUTOCONNECT" = "on" ]; then
  if [ -n "$CITY" ]; then
    nordvpn set autoconnect on "$COUNTRY" "$CITY" >/dev/null 2>&1 || \
      nordvpn set autoconnect on "$COUNTRY" >/dev/null 2>&1 || true
  else
    nordvpn set autoconnect on "$COUNTRY" >/dev/null 2>&1 || true
  fi
else
  nordvpn set autoconnect off >/dev/null 2>&1 || true
fi

say 6/7 "Connecting to ${COUNTRY}${CITY:+ / $CITY}…"
if [ -n "$CITY" ]; then
  nordvpn connect "$COUNTRY" "$CITY" 2>&1 | sed 's|^|      |'
else
  nordvpn connect "$COUNTRY" 2>&1 | sed 's/^/      /'
fi
CONNECTED=0
for i in $(seq 1 60); do
  nordvpn status 2>/dev/null | grep -qi 'Status: Connected' && { CONNECTED=1; break; }
  sleep 2
done
[ "$CONNECTED" = "1" ] || die "Could not reach Connected state for ${COUNTRY}."
nordvpn status | sed 's/^/      /'

say 7/7 "Starting microsocks on 0.0.0.0:${PORT}…"
exec microsocks -i 0.0.0.0 -p "$PORT"
ENTRYPOINT

  chmod +x "$BUILD_DIR/entrypoint.sh"
}

action_build() {
  banner; title "3) $(t m_build)"
  have docker || { bad "Docker missing — run option 1 first."; pause; return; }

  step "Writing build context"
  write_build_files
  ok "$BUILD_DIR/Dockerfile"
  ok "$BUILD_DIR/entrypoint.sh"
  if grep -q '```' "$BUILD_DIR/entrypoint.sh"; then
    bad "Markdown fence found inside entrypoint.sh — aborting."; pause; return
  fi
  bash -n "$BUILD_DIR/entrypoint.sh" && ok "entrypoint.sh syntax OK"

  step "Building image  ($IMAGE)"
  printf '  %sDebian + NordVPN CLI + OpenVPN + wireguard-tools + microsocks.%s\n' "$GRY" "$R"
  printf '  %sFirst build takes a few minutes.%s\n\n' "$GRY" "$R"
  if docker build --pull -t "$IMAGE" "$BUILD_DIR" 2>&1 | sed 's/^/    /'; then
    printf '\n'; ok "Image built: $IMAGE"; log "image built"
  else
    printf '\n'; bad "Build failed. Scroll up for the error."
  fi
  pause
}

# ====================================================== container lifecycle ===
declare -A CFG

cfg_reset() {
  CFG=( [name]="" [country]="United_States" [city]="" [hport]="" [iport]="$DEF_INNER_PORT"
        [bind]="$BIND_ADDR_DEFAULT" [tech]="$DEF_TECH" [proto]="$DEF_PROTO"
        [auto]="$DEF_AUTOCONNECT" [lan]="$DEF_LAN" [analytics]="$DEF_ANALYTICS"
        [token]="$(tok_first)" )
}

cfg_load() {   # cfg_load <container>
  local n="$1" f
  f() { docker inspect "$n" --format "{{index .Config.Labels \"${LABEL_NS}.$1\"}}" 2>/dev/null; }
  cfg_reset
  CFG[name]="$n"
  CFG[country]="$(f country)";  CFG[hport]="$(f port)";  CFG[iport]="$(f iport)"
  CFG[bind]="$(f bind)";        CFG[tech]="$(f tech)";   CFG[proto]="$(f proto)"
  CFG[auto]="$(f auto)";        CFG[lan]="$(f lan)";     CFG[analytics]="$(f analytics)"
  CFG[token]="$(f token)";      CFG[city]="$(f city)"
  [[ "${CFG[token]}" == "<no value>" ]] && CFG[token]=""
  [[ "${CFG[city]}"  == "<no value>" ]] && CFG[city]=""
  [[ -z "${CFG[token]}" ]] && CFG[token]="$(tok_first)"
  [[ -z "${CFG[iport]}" || "${CFG[iport]}" == "<no value>" ]] && CFG[iport]="$DEF_INNER_PORT"
  [[ -z "${CFG[bind]}"  || "${CFG[bind]}"  == "<no value>" ]] && CFG[bind]="$BIND_ADDR_DEFAULT"
  [[ -z "${CFG[tech]}"  || "${CFG[tech]}"  == "<no value>" ]] && CFG[tech]="$DEF_TECH"
  [[ -z "${CFG[proto]}" || "${CFG[proto]}" == "<no value>" ]] && CFG[proto]="$DEF_PROTO"
  [[ -z "${CFG[auto]}"  || "${CFG[auto]}"  == "<no value>" ]] && CFG[auto]="$DEF_AUTOCONNECT"
  [[ -z "${CFG[lan]}"   || "${CFG[lan]}"   == "<no value>" ]] && CFG[lan]="$DEF_LAN"
  [[ -z "${CFG[analytics]}" || "${CFG[analytics]}" == "<no value>" ]] && CFG[analytics]="$DEF_ANALYTICS"
}

cfg_show() {
  printf '\n'
  printf '   %s%s%s %s %s\n' "$GRY" "$(padr "$(t s_country)" 18)"        "$R" "$(country_flag "${CFG[country]}")" "${B}${CFG[country]}${R}"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_city)" 18)"     "$R" "${B}${CFG[city]:-any}${R}"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_token)" 18)"    "$R" "${B}${CFG[token]:-none}${R}"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_tech)" 18)"     "$R" "${B}${CFG[tech]}${R}"
  if [[ "${CFG[tech]}" == "OpenVPN" ]]; then
    printf '   %s%s%s %s\n'  "$GRY" "$(padr "$(t s_proto)" 18)"      "$R" "${B}${CFG[proto]}${R}"
  else
    printf '   %s%s%s %s%s%s\n' "$GRY" "$(padr "$(t s_proto)" 18)"   "$R" "$D" "UDP (NordLynx)" "$R"
  fi
  printf '   %s%s%s %s → container %s\n' "$GRY" "$(padr "socks5" 18)" "$R" \
    "${B}${CFG[bind]}:${CFG[hport]}${R}" "${CFG[iport]}"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_auto)" 18)"   "$R" "$(on_off "${CFG[auto]}")"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_lan)" 18)"  "$R" "$(on_off "${CFG[lan]}")"
  printf '   %s%s%s %s\n'    "$GRY" "$(padr "$(t s_analytics)" 18)"      "$R" "$(on_off "${CFG[analytics]}")"
  printf '\n'
}

wait_connected() {
  local name="$1" timeout="${2:-240}" i=0 out=""
  while (( i < timeout )); do
    if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
      printf '\n'; bad "Container exited early."; docker logs --tail 20 "$name" 2>&1 | sed 's/^/      /'; return 1
    fi
    out="$(docker exec "$name" nordvpn status 2>/dev/null || true)"
    if grep -qi 'Status: Connected' <<<"$out"; then
      progress "$timeout" "$timeout" "connected"; printf '\n'
      printf '%s\n' "$out" | grep -iE 'Server|Country|City|technology|protocol' | sed 's/^/      /'
      return 0
    fi
    progress "$i" "$timeout" "$(t waiting_conn)"
    sleep 2; i=$(( i + 2 ))
  done
  printf '\n'; bad "$(t timeout)"; return 1
}

cfg_create() {   # builds the container described by CFG
  local name="${CFG[name]}"
  if [[ -z "$name" ]]; then
    name="nord-$(( $(loc_count) + 1 ))-$(slug "${CFG[country]}")"
    docker ps -a --format '{{.Names}}' | grep -qx "$name" && name="${name}-${CFG[hport]}"
  fi

  # shellcheck disable=SC2059
  printf "\n  ${BLU}•${R} $(t creating)\n" "$B$name$R" \
    "$(country_flag "${CFG[country]}") ${CFG[country]}" "$B${CFG[hport]}$R"

  local token; token="$(token_get "${CFG[token]}")"
  [[ -z "$token" ]] && { bad "Token not found in the vault: ${CFG[token]}"; return 1; }
  if docker run -d \
      --name "$name" \
      --restart unless-stopped \
      --cap-add=NET_ADMIN \
      --device=/dev/net/tun \
      -p "${CFG[bind]}:${CFG[hport]}:${CFG[iport]}" \
      -e NORD_COUNTRY="${CFG[country]}" \
      -e NORD_CITY="${CFG[city]}" \
      -e NORD_TOKEN="$token" \
      -e NORD_TECH="${CFG[tech]}" \
      -e NORD_PROTO="${CFG[proto]}" \
      -e NORD_AUTOCONNECT="${CFG[auto]}" \
      -e NORD_LAN="${CFG[lan]}" \
      -e NORD_ANALYTICS="${CFG[analytics]}" \
      -e SOCKS_PORT="${CFG[iport]}" \
      --label "${LABEL_NS}.managed=1" \
      --label "${LABEL_NS}.country=${CFG[country]}" \
      --label "${LABEL_NS}.city=${CFG[city]}" \
      --label "${LABEL_NS}.token=${CFG[token]}" \
      --label "${LABEL_NS}.port=${CFG[hport]}" \
      --label "${LABEL_NS}.iport=${CFG[iport]}" \
      --label "${LABEL_NS}.bind=${CFG[bind]}" \
      --label "${LABEL_NS}.tech=${CFG[tech]}" \
      --label "${LABEL_NS}.proto=${CFG[proto]}" \
      --label "${LABEL_NS}.auto=${CFG[auto]}" \
      --label "${LABEL_NS}.lan=${CFG[lan]}" \
      --label "${LABEL_NS}.analytics=${CFG[analytics]}" \
      "$IMAGE" >/dev/null; then
    ok "Container started: $name"
  else
    bad "docker run failed for $name"; return 1
  fi

  wait_connected "$name" 300 || return 1
  local ip; ip="$(curl -s --max-time 15 --proxy "socks5h://127.0.0.1:${CFG[hport]}" https://api.ipify.org || true)"
  [[ -n "$ip" ]] && ok "SOCKS5 live → ${CFG[bind]}:${CFG[hport]}  exit IP ${B}${ip}${R}" \
                 || warn "Tunnel is up but the SOCKS test returned nothing yet."
  log "created $name country=${CFG[country]} port=${CFG[hport]} tech=${CFG[tech]} proto=${CFG[proto]}"
}

preflight() {
  token_ok  || { bad "$(t no_token)"; pause; return 1; }
  image_exists || { bad "$(t no_image)"; pause; return 1; }
  return 0
}

action_add() {
  banner; title "4) $(t m_add)"
  preflight || return
  cfg_reset
  local tkn; tkn="$(pick_token)" || { pause; return; }
  CFG[token]="$tkn"
  banner; title "4) $(t m_add)"
  local c; c="$(pick_country)" || { warn "$(t cancelled)"; pause; return; }
  CFG[country]="$c"
  banner; title "4) $(t m_add)"
  CFG[city]="$(pick_city "$c")"
  banner; title "4) $(t m_add)"
  CFG[tech]="$(pick_tech)"
  if [[ "${CFG[tech]}" == "OpenVPN" ]]; then
    banner; title "4) $(t m_add)"
    CFG[proto]="$(pick_proto)"
  else
    CFG[proto]="UDP"
  fi
  banner; title "4) $(t m_add)"
  printf '\n'
  local p; p="$(ask "$(t port_prompt)" "$(next_free_port)")"
  if ! [[ "$p" =~ ^[0-9]+$ ]] || (( p < 1 || p > 65535 )); then bad "$(t invalid)"; pause; return; fi
  if port_in_use "$p"; then
    # shellcheck disable=SC2059
    printf "  ${RED}✘${R} $(t port_busy)\n" "$p"; pause; return
  fi
  CFG[hport]="$p"
  CFG[iport]="$(ask "$(t inner_port_prompt)" "$DEF_INNER_PORT")"
  CFG[bind]="$(ask "$(t bind_prompt)" "$BIND_ADDR_DEFAULT")"
  [[ "${CFG[bind]}" == "0.0.0.0" ]] && warn "$(t bind_warn)"
  confirm "$(t autoconnect)?" && CFG[auto]="on" || CFG[auto]="off"
  confirm "$(t lan_disc)?"    && CFG[lan]="on"  || CFG[lan]="off"
  confirm "$(t analytics)?"   && CFG[analytics]="on" || CFG[analytics]="off"
  cfg_show
  confirm "Create it?" || { warn "$(t cancelled)"; pause; return; }
  cfg_create
  pause
}

action_batch() {
  banner; title "5) $(t m_batch)"
  preflight || return
  local -a plan=( "United_States|1081" "Turkey|1082" "United_Arab_Emirates|1083"
                  "Australia|1084" "Netherlands|1085" )
  printf '\n'
  local e c p
  for e in "${plan[@]}"; do
    IFS='|' read -r c p <<<"$e"
    printf '   %s %-24s → 127.0.0.1:%s%s%s\n' "$(country_flag "$c")" "$c" "$B" "$p" "$R"
  done
  printf '\n'
  confirm "Create these 5 locations now?" || { warn "$(t cancelled)"; pause; return; }
  cfg_reset
  local tkn; tkn="$(pick_token)" || { pause; return; }
  CFG[token]="$tkn"
  CFG[tech]="$(pick_tech)"
  [[ "${CFG[tech]}" == "OpenVPN" ]] && CFG[proto]="$(pick_proto)" || CFG[proto]="UDP"
  local bind; bind="$(ask "$(t bind_prompt)" "$BIND_ADDR_DEFAULT")"
  local tech="${CFG[tech]}" proto="${CFG[proto]}"
  local i=0
  for e in "${plan[@]}"; do
    IFS='|' read -r c p <<<"$e"
    i=$(( i + 1 ))
    printf '\n  %s─── [%d/5] %s ───%s\n' "$C1" "$i" "$c" "$R"
    if port_in_use "$p"; then warn "Port $p already busy — skipping $c"; continue; fi
    cfg_reset
    CFG[country]="$c"; CFG[hport]="$p"; CFG[bind]="$bind"
    CFG[tech]="$tech"; CFG[proto]="$proto"; CFG[token]="$tkn"
    cfg_create || warn "Continuing with the rest…"
  done
  printf '\n'; ok "$(t done)"
  pause
}

# ====================================================== per-location settings =
action_settings() {
  banner; title "6) $(t m_settings)"
  preflight || return
  local name; name="$(pick_location)" || { pause; return; }
  cfg_load "$name"
  local dirty=0

  while true; do
    banner; title "6) $(t m_settings) — $name"
    printf '\n  %s%s%s' "$B$WHT" "$(t cur_settings)" "$R"
    cfg_show
    (( dirty )) && warn "$(t apply_note)"
    printf '\n'
    menu_item 1 "$(padr "$(t s_country)" 22)${B}${CFG[country]}${R}"
    menu_item 2 "$(padr "$(t s_tech)" 22)${B}${CFG[tech]}${R}"
    if [[ "${CFG[tech]}" == "OpenVPN" ]]; then
      menu_item 3 "$(padr "$(t s_proto)" 22)${B}${CFG[proto]}${R}"
    else
      menu_item 3 "$(padr "$(t s_proto)" 22)${D}UDP (NordLynx)${R}"
    fi
    menu_item 4 "$(padr "$(t s_hport)" 22)${B}${CFG[hport]}${R}"
    menu_item 5 "$(padr "$(t s_iport)" 22)${B}${CFG[iport]}${R}"
    menu_item 6 "$(padr "$(t s_bind)" 22)${B}${CFG[bind]}${R}"
    menu_item 7 "$(padr "$(t s_auto)" 22)$(on_off "${CFG[auto]}")"
    menu_item 8 "$(padr "$(t s_lan)" 22)$(on_off "${CFG[lan]}")"
    menu_item 9 "$(padr "$(t s_analytics)" 22)$(on_off "${CFG[analytics]}")"
    menu_item 10 "$(padr "$(t s_token)" 22)${B}${CFG[token]}${R}"
    menu_item 11 "$(padr "$(t s_city)" 22)${B}${CFG[city]:-any}${R}"
    printf '\n'
    menu_item "A" "${B}${GRN}Apply — recreate the container${R}"
    menu_item 0 "Back (discard)"
    printf '\n'
    case "$(ask "$(t edit_what)" "0")" in
      1) local c; c="$(pick_country)" && { CFG[country]="$c"; CFG[city]="$(pick_city "$c")"; dirty=1; } ;;
      2) CFG[tech]="$(pick_tech)"; [[ "${CFG[tech]}" == "NordLynx" ]] && CFG[proto]="UDP"; dirty=1 ;;
      3) if [[ "${CFG[tech]}" == "NordLynx" ]]; then warn "$(t proto_note)"; sleep 2
         else CFG[proto]="$(pick_proto)"; dirty=1; fi ;;
      4) local p; p="$(ask "$(t port_prompt)" "${CFG[hport]}")"
         if [[ "$p" != "${CFG[hport]}" ]] && port_in_use "$p"; then
           # shellcheck disable=SC2059
           printf "  ${RED}✘${R} $(t port_busy)\n" "$p"; sleep 2
         elif [[ "$p" =~ ^[0-9]+$ ]]; then CFG[hport]="$p"; dirty=1; fi ;;
      5) local ip2; ip2="$(ask "$(t inner_port_prompt)" "${CFG[iport]}")"
         [[ "$ip2" =~ ^[0-9]+$ ]] && { CFG[iport]="$ip2"; dirty=1; } ;;
      6) CFG[bind]="$(ask "$(t bind_prompt)" "${CFG[bind]}")"; dirty=1
         [[ "${CFG[bind]}" == "0.0.0.0" ]] && { warn "$(t bind_warn)"; sleep 2; } ;;
      7) CFG[auto]="$(toggle "${CFG[auto]}")"; dirty=1 ;;
      8) CFG[lan]="$(toggle "${CFG[lan]}")"; dirty=1 ;;
      9) CFG[analytics]="$(toggle "${CFG[analytics]}")"; dirty=1 ;;
      10) local tn; tn="$(pick_token)" && { CFG[token]="$tn"; dirty=1; } ;;
      11) CFG[city]="$(pick_city "${CFG[country]}")"; dirty=1 ;;
      a|A)
         if (( ! dirty )); then info "Nothing changed."; sleep 1; continue; fi
         printf '\n'; confirm "$(t applying)?" || continue
         spin_run "Removing old container" docker rm -f "$name"
         cfg_create
         log "settings applied to $name"
         pause; return ;;
      0|"") return ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
  done
}

action_defaults() {
  while true; do
    banner; title "$(t m_defaults)"
    printf '\n  %s%s%s\n\n' "$GRY" "$(t defaults_title)" "$R"
    menu_item 1 "$(padr "$(t s_tech)" 22)${B}${DEF_TECH}${R}"
    menu_item 2 "$(padr "$(t s_proto)" 22)${B}${DEF_PROTO}${R}"
    menu_item 3 "$(padr "$(t s_auto)" 22)$(on_off "$DEF_AUTOCONNECT")"
    menu_item 4 "$(padr "$(t s_lan)" 22)$(on_off "$DEF_LAN")"
    menu_item 5 "$(padr "$(t s_analytics)" 22)$(on_off "$DEF_ANALYTICS")"
    menu_item 6 "$(padr "$(t s_iport)" 22)${B}${DEF_INNER_PORT}${R}"
    menu_item 7 "$(padr "$(t s_bind)" 22)${B}${BIND_ADDR_DEFAULT}${R}"
    printf '\n'
    menu_item 0 "Back"
    printf '\n'
    case "$(ask "$(t choose)" "0")" in
      1) DEF_TECH="$(pick_tech)"; [[ "$DEF_TECH" == "NordLynx" ]] && DEF_PROTO="UDP" ;;
      2) if [[ "$DEF_TECH" == "NordLynx" ]]; then warn "$(t proto_note)"; sleep 2
         else DEF_PROTO="$(pick_proto)"; fi ;;
      3) DEF_AUTOCONNECT="$(toggle "$DEF_AUTOCONNECT")" ;;
      4) DEF_LAN="$(toggle "$DEF_LAN")" ;;
      5) DEF_ANALYTICS="$(toggle "$DEF_ANALYTICS")" ;;
      6) DEF_INNER_PORT="$(ask "$(t inner_port_prompt)" "$DEF_INNER_PORT")" ;;
      7) BIND_ADDR_DEFAULT="$(ask "$(t bind_prompt)" "$BIND_ADDR_DEFAULT")" ;;
      0|"") save_conf; return ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
    save_conf
  done
}

# =============================================================== dashboard ====
vpn_state() {
  local out; out="$(docker exec "$1" nordvpn status 2>/dev/null || true)"
  if grep -qi 'Status: Connected' <<<"$out"; then printf 'Connected'
  elif [[ -n "$out" ]]; then printf 'Disconnected'
  else printf '-'; fi
}

proxy_geo() {
  local j; j="$(curl -s --max-time 12 --proxy "socks5h://127.0.0.1:$1" https://ipinfo.io/json 2>/dev/null)"
  [[ -z "$j" ]] && { printf '|'; return; }
  local ip cc
  if have jq; then ip="$(jq -r '.ip // ""' <<<"$j")"; cc="$(jq -r '.country // ""' <<<"$j")"
  else ip="$(sed -n 's/.*"ip"[ ]*:[ ]*"\([^"]*\)".*/\1/p' <<<"$j")"
       cc="$(sed -n 's/.*"country"[ ]*:[ ]*"\([^"]*\)".*/\1/p' <<<"$j")"; fi
  printf '%s|%s' "$ip" "$cc"
}

action_status() {
  banner; title "7) $(t m_status)"
  local rows; rows="$(list_locations)"
  if [[ -z "$rows" ]]; then printf '\n'; warn "$(t no_loc)"; pause; return; fi

  printf '\n  %s%-20s %-3s %-20s %-7s %-9s %-5s %-10s %-11s%s\n' "$B$GRY" \
    "CONTAINER" "" "COUNTRY" "PORT" "TECH" "PROTO" "DOCKER" "VPN" "$R"
  printf '  %s%s%s\n' "$GRY" "$(printf '─%.0s' $(seq 1 92))" "$R"

  local n c p b s tech proto ipn tokn city vs dcol vcol
  while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
    [[ -z "$n" ]] && continue
    if [[ "$s" == "running" ]]; then vs="$(vpn_state "$n")"; else vs="-"; fi
    dcol="$RED"; [[ "$s" == "running" ]] && dcol="$GRN"
    vcol="$RED"; [[ "$vs" == "Connected" ]] && vcol="$GRN"
    [[ "$tech" == "NordLynx" ]] && proto="UDP"
    printf '  %-20s %-3s %-20s %s%-7s%s %-9s %-5s %s%-10s%s %s%-11s%s\n' \
      "$n" "$(country_flag "$c")" "$c" "$B" "$p" "$R" "${tech:-?}" "${proto:-?}" \
      "$dcol" "$s" "$R" "$vcol" "$vs" "$R"
  done <<<"$rows"

  printf '\n  %sImage:%s %s   %sLog:%s %s\n' "$GRY" "$R" "$IMAGE" "$GRY" "$R" "$LOG_FILE"
  printf '\n  %sHost listeners:%s\n' "$GRY" "$R"
  have ss && { ss -lntp 2>/dev/null | grep -E ':(1[0-9]{3})' | sed 's/^/    /' || printf '    (none)\n'; }
  pause
}

action_test() {
  banner; title "8) $(t m_test)"
  local rows; rows="$(list_locations)"
  if [[ -z "$rows" ]]; then printf '\n'; warn "$(t no_loc)"; pause; return; fi
  printf '\n  %s%s%s\n\n' "$GRY" "$(t testing)" "$R"
  printf '  %s%-20s %-20s %-7s %-16s %-6s %s%s\n' "$B$GRY" \
    "CONTAINER" "EXPECTED" "PORT" "EXIT IP" "GEO" "VERDICT" "$R"
  printf '  %s%s%s\n' "$GRY" "$(printf '─%.0s' $(seq 1 86))" "$R"
  local n c p b s tech proto ipn tokn city ip cc geo verdict vcol
  while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
    [[ -z "$n" ]] && continue
    geo="$(proxy_geo "$p")"; ip="${geo%%|*}"; cc="${geo##*|}"
    if [[ -z "$ip" ]]; then verdict="FAIL"; vcol="$RED"; ip="—"; cc="—"
    else verdict="OK"; vcol="$GRN"; fi
    printf '  %-20s %-20s %s%-7s%s %-16s %-6s %s%s%s\n' \
      "$n" "$c" "$B" "$p" "$R" "$ip" "$cc" "$vcol" "$verdict" "$R"
  done <<<"$rows"
  printf '\n  %sTip: curl --proxy socks5h://127.0.0.1:PORT https://api.ipify.org%s\n' "$GRY" "$R"
  pause
}

action_logs() {
  banner; title "9) $(t m_logs)"
  local name; name="$(pick_location)" || { pause; return; }
  printf '\n  %sLast 60 lines — Ctrl+C to leave the live tail.%s\n\n' "$GRY" "$R"
  docker logs --tail 60 -f "$name" 2>&1 | sed 's/^/    /' || true
  pause
}

action_power() {
  banner; title "10) $(t m_restart)"
  local name; name="$(pick_location)" || { pause; return; }
  printf '\n'
  menu_item 1 "Restart"; menu_item 2 "Stop"; menu_item 3 "Start"
  printf '\n'
  case "$(ask "$(t choose)" "1")" in
    1) spin_run "Restarting $name" docker restart "$name"; wait_connected "$name" 300 ;;
    2) spin_run "Stopping $name"  docker stop "$name" ;;
    3) spin_run "Starting $name"  docker start "$name"; wait_connected "$name" 300 ;;
    *) bad "$(t invalid)" ;;
  esac
  pause
}

action_delete() {
  banner; title "11) $(t m_del)"
  local name; name="$(pick_location)" || { pause; return; }
  printf '\n'
  local q; q="$(printf "$(t confirm_del)" "$name")"
  confirm "$q" || { warn "$(t cancelled)"; pause; return; }
  spin_run "Removing $name" docker rm -f "$name"
  log "deleted $name"
  pause
}

# ================================================================= export =====
action_export() {
  banner; title "12) $(t m_export)"
  local rows; rows="$(list_locations)"
  if [[ -z "$rows" ]]; then printf '\n'; warn "$(t no_loc)"; pause; return; fi
  local host; host="$(ask "Address Marzban/Pasarguard should dial (127.0.0.1 if same host)" "127.0.0.1")"
  mkdir -p "$EXPORT_DIR"
  local out="$EXPORT_DIR/outbounds.json" rules="$EXPORT_DIR/routing-rules.json"

  {
    printf '[\n'
    local first=1 n c p b s tech proto ipn tokn city tag
    while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
      [[ -z "$n" ]] && continue
      tag="$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]' | cut -c1-24)"
      (( first )) || printf ',\n'; first=0
      printf '  {\n    "tag": "NORD-%s",\n    "protocol": "socks",\n' "$tag"
      printf '    "settings": { "servers": [ { "address": "%s", "port": %s } ] },\n' "$host" "$p"
      printf '    "streamSettings": { "network": "tcp" }\n  }'
    done <<<"$rows"
    printf '\n]\n'
  } >"$out"

  {
    printf '{\n  "domainStrategy": "IPIfNonMatch",\n  "rules": [\n'
    local first=1 n c p b s tech proto ipn tokn city tag
    while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
      [[ -z "$n" ]] && continue
      tag="$(printf '%s' "$c" | tr '[:lower:]' '[:upper:]' | cut -c1-24)"
      (( first )) || printf ',\n'; first=0
      printf '    { "type": "field", "domain": ["geosite:REPLACE_ME"], "outboundTag": "NORD-%s" }' "$tag"
    done <<<"$rows"
    printf '\n  ]\n}\n'
  } >"$rules"

  printf '\n'; ok "Outbounds  → $out"; ok "Routing    → $rules"
  printf '\n  %s─── outbounds.json ───%s\n' "$C1" "$R"
  sed 's/^/    /' "$out"
  pause
}

# ============================================================== wireguard =====
wg_dump() { docker exec "$1" wg show nordlynx dump 2>/dev/null; }

wg_build_conf() {   # wg_build_conf <container> -> config on stdout, "" on failure
  local n="$1" dump priv peer endpoint keep addr
  dump="$(wg_dump "$n")" || return 1
  [[ -z "$dump" ]] && return 1
  priv="$(printf '%s\n' "$dump" | sed -n '1p' | cut -f1)"
  peer="$(printf '%s\n' "$dump" | sed -n '2p' | cut -f1)"
  endpoint="$(printf '%s\n' "$dump" | sed -n '2p' | cut -f3)"
  keep="$(printf '%s\n' "$dump" | sed -n '2p' | cut -f8)"
  [[ -z "$keep" || "$keep" == "off" || "$keep" == "0" ]] && keep=25
  addr="$(docker exec "$n" ip -4 -o addr show nordlynx 2>/dev/null | awk '{print $4}')"
  [[ -z "$addr" ]] && addr="10.5.0.2/32"
  [[ -z "$priv" || -z "$peer" || -z "$endpoint" ]] && return 1
  cat <<CONF
[Interface]
PrivateKey = $priv
Address = $addr
DNS = 103.86.96.100

[Peer]
PublicKey = $peer
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $endpoint
PersistentKeepalive = $keep
CONF
}

action_wg() {
  banner; title "13) $(t m_wg)"
  local name; name="$(pick_location)" || { pause; return; }
  cfg_load "$name"
  if [[ "${CFG[tech]}" != "NordLynx" ]]; then
    printf '\n'; bad "$(t wg_only_lynx)"; pause; return
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "$name"; then
    printf '\n'; bad "Container is not running."; pause; return
  fi

  while true; do
    banner; title "13) $(t m_wg) — $name"
    printf '\n  %s%s%s\n\n' "$YLW" "$(t wg_secret)" "$R"
    menu_item 1 "Show private key"
    menu_item 2 "Show full WireGuard config"
    menu_item 3 "Save config to a file"
    menu_item 4 "Show QR code (for the WireGuard mobile app)"
    menu_item 5 "Show raw interface state (wg show)"
    printf '\n'; menu_item 0 "Back"; printf '\n'
    case "$(ask "$(t choose)" "0")" in
      1) local k; k="$(docker exec "$name" wg show nordlynx private-key 2>/dev/null)"
         printf '\n'
         if [[ -n "$k" ]]; then printf '    %s%s%s\n' "$B$WHT" "$k" "$R"
         else bad "Could not read the key — is NordLynx connected?"; fi
         pause ;;
      2) local conf; conf="$(wg_build_conf "$name")"
         printf '\n'
         if [[ -n "$conf" ]]; then printf '%s\n' "$conf" | sed 's/^/    /'
         else bad "Could not assemble the config."; fi
         pause ;;
      3) local conf f; conf="$(wg_build_conf "$name")"
         if [[ -z "$conf" ]]; then printf '\n'; bad "Could not assemble the config."; pause; continue; fi
         mkdir -p "$EXPORT_DIR"; f="$EXPORT_DIR/${name}.conf"
         printf '%s\n' "$conf" >"$f"; chmod 600 "$f"
         printf '\n'
         # shellcheck disable=SC2059
         printf "  ${GRN}✔${R} $(t wg_saved)\n" "$f"
         warn "This file is a credential — mode 600, never commit it."
         pause ;;
      4) local conf; conf="$(wg_build_conf "$name")"
         if [[ -z "$conf" ]]; then printf '\n'; bad "Could not assemble the config."; pause; continue; fi
         if have qrencode; then
           printf '\n'; printf '%s\n' "$conf" | qrencode -t ansiutf8
           warn "Anyone who scans this owns the key. Clear your screen afterwards."
         else
           printf '\n'; bad "qrencode is not installed — run menu option 1."
         fi
         pause ;;
      5) printf '\n'; docker exec "$name" wg show 2>&1 | sed 's/^/    /'; pause ;;
      0|"") return ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
  done
}

# ================================================================= healer =====
healer_installed() { crontab -l 2>/dev/null | grep -q "$HEALER_FILE"; }

write_healer() {
  cat >"$HEALER_FILE" <<'HEAL'
#!/usr/bin/env bash
# nordlynx auto-healer: restarts any managed proxy whose SOCKS exit is dead.
LABEL_NS="nlm"
LOG="/opt/nordlynx-manager/healer.log"
docker ps -a --filter "label=${LABEL_NS}.managed=1" \
  --format '{{.Names}}\t{{.Label "'"${LABEL_NS}"'.port"}}\t{{.State}}' |
while IFS=$'\t' read -r name port state; do
  [ -z "$name" ] && continue
  if [ "$state" != "running" ]; then
    echo "[$(date '+%F %T')] $name not running -> start" >>"$LOG"
    docker start "$name" >/dev/null 2>&1
    continue
  fi
  if ! curl -s --max-time 20 --proxy "socks5h://127.0.0.1:${port}" https://api.ipify.org >/dev/null; then
    echo "[$(date '+%F %T')] $name proxy dead on $port -> restart" >>"$LOG"
    docker restart "$name" >/dev/null 2>&1
  fi
done
HEAL
  chmod +x "$HEALER_FILE"
}

action_healer() {
  banner; title "14) $(t m_healer)"
  printf '\n'
  healer_installed && ok "Watchdog is ACTIVE (every 5 minutes)" || warn "Watchdog is not installed"
  printf '\n'
  menu_item 1 "Enable / reinstall watchdog (cron */5)"
  menu_item 2 "Disable watchdog"
  menu_item 3 "Run one healing pass now"
  menu_item 4 "Show healer log"
  menu_item 0 "Back"
  printf '\n'
  case "$(ask "$(t choose)" "0")" in
    1) write_healer
       ( crontab -l 2>/dev/null | grep -v "$HEALER_FILE"; echo "*/5 * * * * $HEALER_FILE" ) | crontab -
       ok "Installed: */5 * * * * $HEALER_FILE" ;;
    2) crontab -l 2>/dev/null | grep -v "$HEALER_FILE" | crontab -; ok "Watchdog removed" ;;
    3) write_healer; spin_run "Healing pass" bash "$HEALER_FILE"; ok "$(t done)" ;;
    4) [[ -f "$APP_DIR/healer.log" ]] && tail -n 30 "$APP_DIR/healer.log" | sed 's/^/    /' || info "No healer log yet." ;;
    0|"") return ;;
    *) bad "$(t invalid)" ;;
  esac
  pause
}

# ================================================================= backup =====
action_backup() {
  banner; title "15) $(t m_backup)"
  printf '\n'
  menu_item 1 "Create backup"
  menu_item 2 "Restore from backup (recreate all locations)"
  menu_item 3 "List backups"
  menu_item 0 "Back"
  printf '\n'
  case "$(ask "$(t choose)" "0")" in
    1) mkdir -p "$BACKUP_DIR"
       local stamp; stamp="$(date '+%Y%m%d-%H%M%S')"
       local man="$BACKUP_DIR/locations-$stamp.tsv"
       list_locations >"$man"
       local tgz="$BACKUP_DIR/nordlynx-$stamp.tar.gz"
       tar -czf "$tgz" -C "$APP_DIR" --exclude backups . 2>/dev/null
       chmod 600 "$tgz" "$man"
       ok "Manifest → $man"
       ok "Archive  → $tgz  (contains your token — keep it private)" ;;
    2) local -a files=(); mapfile -t files < <(ls -1t "$BACKUP_DIR"/locations-*.tsv 2>/dev/null)
       if (( ${#files[@]} == 0 )); then warn "No manifests found."; pause; return; fi
       printf '\n'; local i
       for i in "${!files[@]}"; do menu_item $(( i + 1 )) "$(basename "${files[$i]}")"; done
       printf '\n'
       local sel; sel="$(ask "$(t choose)" "1")"
       [[ "$sel" =~ ^[0-9]+$ ]] || { bad "$(t invalid)"; pause; return; }
       local man="${files[$(( sel - 1 ))]}"
       preflight || return
       local n c p b s tech proto ipn tokn city
       while IFS=$'\t' read -r n c p b s tech proto ipn tokn city; do
         [[ -z "$n" ]] && continue
         docker ps -a --format '{{.Names}}' | grep -qx "$n" && { warn "$n exists — skipping"; continue; }
         cfg_reset
         CFG[name]="$n"; CFG[country]="$c"; CFG[hport]="$p"
         [[ -n "$b"     && "$b" != "<no value>"     ]] && CFG[bind]="$b"
         [[ -n "$tech"  && "$tech" != "<no value>"  ]] && CFG[tech]="$tech"
         [[ -n "$proto" && "$proto" != "<no value>" ]] && CFG[proto]="$proto"
         [[ -n "$ipn"   && "$ipn" != "<no value>"   ]] && CFG[iport]="$ipn"
         cfg_create
       done <"$man"
       ok "$(t done)" ;;
    3) ls -lh "$BACKUP_DIR" 2>/dev/null | sed 's/^/    /' || info "empty" ;;
    0|"") return ;;
    *) bad "$(t invalid)" ;;
  esac
  pause
}

# =============================================================== language =====
action_lang() {
  local k="m_add"
  while true; do
    banner; title "$(t m_lang)"
    printf '\n  %sPick the one that renders correctly in YOUR terminal.%s\n' "$GRY" "$R"
    printf '  %sThe preview below is the same menu label in each mode.%s\n\n' "$GRY" "$R"

    lang_row() {   # <code> <num> <name> <note> <preview>
      local mark="   "; [[ "$UI_LANG" == "$1" ]] && mark=" ${GRN}▶${R} "
      printf '%s%s%2s%s  %-20s %s%s%s\n' "$mark" "$B$C3" "$2" "$R" "$3" "$GRY" "$4" "$R"
      printf '        %spreview:%s %s\n\n' "$D" "$R" "$5"
    }
    lang_row en     1 "English"        "latin, always safe"                 "${T_en[$k]}"
    lang_row ru     2 "Русский"        "cyrillic, renders everywhere"       "${T_ru[$k]}"
    lang_row zh     3 "简体中文"        "needs a CJK-capable font"           "${T_zh[$k]}"
    lang_row fi     4 "Finglish"       "Persian in latin — recommended"     "${T_fi[$k]}"
    lang_row fa     5 "فارسی (shaped)" "joined letters, visual order"       "${T_fs[$k]}"
    lang_row fa-raw 6 "فارسی (raw)"    "logical order, bidi terminals only" "${T_fa[$k]}"

    printf '    %s0%s  Back\n\n' "$B$C3" "$R"
    case "$(ask "Select 1-6 (0 = back)" "")" in
      1) UI_LANG="en" ;;     2) UI_LANG="ru" ;;     3) UI_LANG="zh" ;;
      4) UI_LANG="fi" ;;     5) UI_LANG="fa" ;;     6) UI_LANG="fa-raw" ;;
      0|"") return ;;
      *) bad "$(t invalid)"; sleep 1; continue ;;
    esac
    save_conf; ok "$(t saved) — $(lang_name)"; sleep 1; return
  done
}

# =============================================================== telegram =====
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

tg_load() { [[ -f "$TG_CONF" ]] && . "$TG_CONF" 2>/dev/null || true; TG_BOT_TOKEN="${TG_BOT_TOKEN:-}"; TG_ADMINS="${TG_ADMINS:-}"; }
tg_save() {
  mkdir -p "$APP_DIR"
  printf 'TG_BOT_TOKEN=%s\nTG_ADMINS=%s\n' "$TG_BOT_TOKEN" "$TG_ADMINS" >"$TG_CONF"
  chmod 600 "$TG_CONF"
}
tg_admin_list() { printf '%s' "$TG_ADMINS" | tr ',' '\n' | grep -v '^$'; }
tg_admin_add() {
  local id="$1"
  tg_admin_list | grep -qx "$id" && return 0
  [[ -z "$TG_ADMINS" ]] && TG_ADMINS="$id" || TG_ADMINS="${TG_ADMINS},${id}"
}
tg_admin_del() { TG_ADMINS="$(tg_admin_list | grep -vx "$1" | paste -sd, -)"; }

bot_installed() { [[ -x "$BOT_FILE" ]]; }
bot_active()    { systemctl is-active --quiet nordlynx-bot 2>/dev/null; }

bot_install_files() {
  local src="$SCRIPT_DIR/nordlynx-bot.sh"
  [[ -f "$src" ]] || src="$SRC_DIR/nordlynx-bot.sh"
  if [[ ! -f "$src" ]]; then
    spin_run "Downloading nordlynx-bot.sh from GitHub" fetch_sources || {
      bad "nordlynx-bot.sh not found and could not be downloaded."; return 1; }
    src="$SRC_DIR/nordlynx-bot.sh"
  fi
  install -m 0700 "$src" "$BOT_FILE"
  if [[ -f "${BASH_SOURCE[0]}" ]]; then
    install -m 0755 "${BASH_SOURCE[0]}" /usr/local/bin/nordlynx
  elif [[ -f "$SRC_DIR/nordlynx-manager.sh" ]]; then
    install -m 0755 "$SRC_DIR/nordlynx-manager.sh" /usr/local/bin/nordlynx
  fi
  cat >/etc/systemd/system/nordlynx-bot.service <<UNIT
[Unit]
Description=NordLynx Manager Telegram bot
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$BOT_FILE
Restart=always
RestartSec=5
Environment=NLM_HOME=$APP_DIR

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  return 0
}

# ========================================================== bootstrap/update ==
# Running via  bash <(curl …)  means $0 is a pipe: no sibling files, nothing to
# install from. In that case fetch the real files to $SRC_DIR and re-exec.
running_from_pipe() {
  local self="${BASH_SOURCE[0]}"
  [[ -f "$self" ]] || return 0
  case "$self" in /dev/fd/*|/proc/self/fd/*|/dev/std*) return 0 ;; esac
  return 1
}

fetch_sources() {   # downloads manager + bot into $SRC_DIR
  mkdir -p "$SRC_DIR"; chmod 700 "$APP_DIR" 2>/dev/null
  local ok=1
  curl -fsSL "$REPO_RAW/nordlynx-manager.sh" -o "$SRC_DIR/nordlynx-manager.sh.new" || ok=0
  curl -fsSL "$REPO_RAW/nordlynx-bot.sh"     -o "$SRC_DIR/nordlynx-bot.sh.new"     || ok=0
  (( ok )) || { rm -f "$SRC_DIR"/*.new; return 1; }
  bash -n "$SRC_DIR/nordlynx-manager.sh.new" || { rm -f "$SRC_DIR"/*.new; return 1; }
  bash -n "$SRC_DIR/nordlynx-bot.sh.new"     || { rm -f "$SRC_DIR"/*.new; return 1; }
  mv "$SRC_DIR/nordlynx-manager.sh.new" "$SRC_DIR/nordlynx-manager.sh"
  mv "$SRC_DIR/nordlynx-bot.sh.new"     "$SRC_DIR/nordlynx-bot.sh"
  chmod 0755 "$SRC_DIR/nordlynx-manager.sh"; chmod 0700 "$SRC_DIR/nordlynx-bot.sh"
  install -m 0755 "$SRC_DIR/nordlynx-manager.sh" /usr/local/bin/nordlynx
  return 0
}

bootstrap() {
  banner
  info "Running from a pipe — installing a real copy first."
  have curl || { apt-get update -qq >/dev/null 2>&1; DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl >/dev/null 2>&1; }
  if ! spin_run "Downloading nordlynx-manager.sh + nordlynx-bot.sh" fetch_sources; then
    bad "Download failed. Check the server's network or GitHub reachability."
    exit 1
  fi
  ok "Installed → $SRC_DIR"
  ok "Command   → nordlynx   (just type: sudo nordlynx)"
  sleep 2
  NLM_BOOTSTRAPPED=1 exec "$SRC_DIR/nordlynx-manager.sh" "$@"
}

action_update() {
  banner; title "$(t m_update)"
  printf '\n  %sSource: %s%s\n\n' "$GRY" "$REPO_RAW" "$R"
  info "current version: $VERSION"
  if spin_run "Fetching the latest files" fetch_sources; then
    local newv; newv="$(grep -m1 '^VERSION=' "$SRC_DIR/nordlynx-manager.sh" | cut -d'"' -f2)"
    ok "installed version: $newv"
    if [[ -x "$BOT_FILE" ]]; then
      install -m 0700 "$SRC_DIR/nordlynx-bot.sh" "$BOT_FILE"
      systemctl restart nordlynx-bot 2>/dev/null && ok "bot restarted"
    fi
    printf '\n'
    if confirm "Restart the menu now to run the new version?"; then
      exec "$SRC_DIR/nordlynx-manager.sh"
    fi
  else
    bad "Update failed — GitHub unreachable, or the file has a syntax error."
    warn "raw.githubusercontent.com caches for a few minutes after a push."
  fi
  pause
}

tg_api() {   # tg_api <method> [curl args…]
  curl -s -m 20 "https://api.telegram.org/bot${TG_BOT_TOKEN}/$1" "${@:2}"
}

action_telegram() {
  tg_load
  while true; do
    banner; title "$(t m_telegram)"
    printf '\n'
    local tokmark="$RED✘$R"; [[ -n "$TG_BOT_TOKEN" ]] && tokmark="$GRN✔$R"
    local admins; admins="$(tg_admin_list | paste -sd' ' -)"
    printf '   %sbot token%s %s   %sadmins%s %s%s%s   %sservice%s %s\n\n' \
      "$GRY" "$R" "$tokmark" "$GRY" "$R" "$B" "${admins:-none}" "$R" \
      "$GRY" "$R" "$(bot_active && printf '%srunning%s' "$GRN" "$R" || printf '%sstopped%s' "$GRY" "$R")"
    menu_item 1 "Set bot token (from @BotFather)"
    menu_item 2 "Add an admin Telegram ID"
    menu_item 3 "Remove an admin ID"
    menu_item 4 "Install / update the bot service"
    menu_item 5 "Start the bot"
    menu_item 6 "Stop the bot"
    menu_item 7 "Bot logs (last 40 lines)"
    menu_item 8 "Send a test message to all admins"
    menu_item 9 "Run the bot in the foreground (debug)"
    printf '\n'; menu_item 0 "Back"; printf '\n'
    case "$(ask "$(t choose)" "0")" in
      1) printf '  %s?%s Bot token: ' "$MAG" "$R"
         local bt; read -rs bt || true; printf '\n'
         bt="$(printf '%s' "$bt" | tr -d '[:space:]')"
         if [[ -z "$bt" ]]; then warn "$(t cancelled)"; sleep 1; continue; fi
         TG_BOT_TOKEN="$bt"; tg_save
         local who; who="$(tg_api getMe | grep -o '"username":"[^"]*"' | cut -d'"' -f4)"
         [[ -n "$who" ]] && ok "Connected to @$who" || bad "Telegram rejected that token."
         sleep 2 ;;
      2) local id; id="$(ask "Telegram numeric user ID (get it from @userinfobot)" "")"
         id="$(printf '%s' "$id" | tr -cd '0-9')"
         [[ -z "$id" ]] && { bad "$(t invalid)"; sleep 1; continue; }
         tg_admin_add "$id"; tg_save; ok "Admin added: $id"; sleep 1 ;;
      3) local -a ids=(); mapfile -t ids < <(tg_admin_list)
         (( ${#ids[@]} == 0 )) && { warn "No admins yet."; sleep 1; continue; }
         printf '\n'; local i
         for i in "${!ids[@]}"; do menu_item $(( i + 1 )) "${ids[$i]}"; done
         printf '\n'
         local sel; sel="$(ask "$(t choose)" "")"
         [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= ${#ids[@]} )) || continue
         tg_admin_del "${ids[$(( sel - 1 ))]}"; tg_save; ok "$(t done)"; sleep 1 ;;
      4) if [[ -z "$TG_BOT_TOKEN" || -z "$TG_ADMINS" ]]; then
           bad "Set the bot token and at least one admin ID first."; sleep 2; continue; fi
         bot_install_files || { pause; continue; }
         systemctl enable --now nordlynx-bot >/dev/null 2>&1
         ok "Service installed and started (nordlynx-bot)"
         info "Open your bot in Telegram and send /start"
         sleep 2 ;;
      5) systemctl start nordlynx-bot && ok "started"; sleep 1 ;;
      6) systemctl stop  nordlynx-bot && ok "stopped"; sleep 1 ;;
      7) journalctl -u nordlynx-bot -n 40 --no-pager 2>/dev/null | sed 's/^/    /'; pause ;;
      8) local id
         for id in $(tg_admin_list); do
           tg_api sendMessage -d chat_id="$id" \
             --data-urlencode "text=✅ NordLynx Manager test message — the bot can reach you." >/dev/null
           ok "sent → $id"
         done
         sleep 2 ;;
      9) bot_installed || bot_install_files || { pause; continue; }
         printf '\n  %sCtrl+C to stop.%s\n\n' "$GRY" "$R"
         "$BOT_FILE" ;;
      0|"") return ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
  done
}

# =================================================================== conf =====
save_conf() {
  mkdir -p "$APP_DIR"
  cat >"$CONF_FILE" <<EOF
UI_LANG=$UI_LANG
DEF_TECH=$DEF_TECH
DEF_PROTO=$DEF_PROTO
DEF_AUTOCONNECT=$DEF_AUTOCONNECT
DEF_LAN=$DEF_LAN
DEF_ANALYTICS=$DEF_ANALYTICS
DEF_INNER_PORT=$DEF_INNER_PORT
BIND_ADDR_DEFAULT=$BIND_ADDR_DEFAULT
EOF
  chmod 600 "$CONF_FILE"
}
load_conf() { [[ -f "$CONF_FILE" ]] && . "$CONF_FILE" 2>/dev/null || true; }

health_line() {
  local locs; locs="$(loc_count)"
  local tk="$RED✘$R"; token_ok && tk="$GRN✔$R"
  local im="$RED✘$R"; image_exists && im="$GRN✔$R"
  local dk="$RED✘$R"; docker info >/dev/null 2>&1 && dk="$GRN✔$R"
  local hl="$GRY○$R"; healer_installed && hl="$GRN●$R"
  printf '  %sdocker%s %s   %stoken%s %s   %simage%s %s   %slocations%s %s%s%s   %swatchdog%s %s   %sdefault%s %s%s/%s%s\n\n' \
    "$GRY" "$R" "$dk" "$GRY" "$R" "$tk" "$GRY" "$R" "$im" \
    "$GRY" "$R" "$B" "$locs" "$R" "$GRY" "$R" "$hl" \
    "$GRY" "$R" "$D" "$DEF_TECH" "$DEF_PROTO" "$R"
}

main_menu() {
  while true; do
    banner
    health_line
    printf '  %s%s%s\n\n' "$B$WHT" "$(t menu)" "$R"
    menu_item  1 "$(t m_deps)"
    menu_item  2 "$(t m_tokens)"
    menu_item  3 "$(t m_build)"
    printf '\n'
    menu_item  4 "$(t m_add)"
    menu_item  5 "${B}$(t m_batch)${R}"
    menu_item  6 "$(t m_settings)"
    printf '\n'
    menu_item  7 "$(t m_status)"
    menu_item  8 "$(t m_test)"
    menu_item  9 "$(t m_logs)"
    menu_item 10 "$(t m_restart)"
    menu_item 11 "$(t m_del)"
    printf '\n'
    menu_item 12 "$(t m_export)"
    menu_item 13 "$(t m_wg)"
    menu_item 14 "$(t m_healer)"
    menu_item 15 "$(t m_backup)"
    menu_item 16 "$(t m_defaults)"
    menu_item 17 "${B}$(t m_telegram)${R}"
    menu_item 18 "$(t m_lang)"
    menu_item 19 "$(t m_update)"
    printf '\n'
    menu_item  0 "$(t m_quit)"
    printf '\n'
    case "$(ask "$(t choose)" "")" in
      1) action_deps ;;    2) action_token ;;   3) action_build ;;
      4) action_add ;;     5) action_batch ;;   6) action_settings ;;
      7) action_status ;;  8) action_test ;;    9) action_logs ;;
      10) action_power ;;  11) action_delete ;;
      12) action_export ;; 13) action_wg ;;     14) action_healer ;;
      15) action_backup ;; 16) action_defaults ;; 17) action_telegram ;;
      18) action_lang ;;    19) action_update ;;
      0|q|Q) banner; printf '  %sBye.%s\n\n' "$GRN" "$R"; exit 0 ;;
      *) bad "$(t invalid)"; sleep 1 ;;
    esac
  done
}

usage() {
  cat <<USAGE
$APP_NAME v$VERSION

  nordlynx-manager.sh                 interactive menu (default)
  nordlynx-manager.sh --list          list managed locations
  nordlynx-manager.sh --status        status table
  nordlynx-manager.sh --test          test every proxy exit IP
  nordlynx-manager.sh --export        write Marzban/Pasarguard outbounds
  nordlynx-manager.sh --wg NAME       print the WireGuard config of a location
  nordlynx-manager.sh --heal          run one auto-heal pass
  nordlynx-manager.sh --update        pull the latest version from GitHub
  nordlynx-manager.sh --bot           run the Telegram bot in the foreground
  nordlynx-manager.sh --install       copy itself to /usr/local/bin/nordlynx
  nordlynx-manager.sh --version|-v
  nordlynx-manager.sh --help|-h
USAGE
}

self_install() {
  if [[ -f "${BASH_SOURCE[0]}" ]]; then
    install -m 0755 "${BASH_SOURCE[0]}" /usr/local/bin/nordlynx
  else
    fetch_sources || { bad "Could not download the sources."; return 1; }
  fi
  [[ -f "$SRC_DIR/nordlynx-bot.sh" ]] || fetch_sources >/dev/null 2>&1
  ok "Installed → /usr/local/bin/nordlynx  (run: sudo nordlynx)"
}

main() {
  case "${1:-}" in
    --help|-h)    usage; exit 0 ;;
    --version|-v) printf '%s v%s\n' "$APP_NAME" "$VERSION"; exit 0 ;;
  esac
  need_root
  mkdir -p "$APP_DIR"; chmod 700 "$APP_DIR"
  load_conf
  if [[ "${NLM_BOOTSTRAPPED:-0}" != "1" ]] && running_from_pipe; then
    bootstrap "$@"
  fi
  case "${1:-}" in
    --list)    list_locations ;;
    --status)  action_status ;;
    --test)    action_test ;;
    --export)  action_export ;;
    --wg)      [[ -n "${2:-}" ]] || { bad "usage: --wg CONTAINER_NAME"; exit 1; }
               wg_build_conf "$2" || { bad "Could not build a config for $2"; exit 1; } ;;
    --heal)    write_healer; bash "$HEALER_FILE"; ok "$(t done)" ;;
    --install) self_install ;;
    --update)  action_update ;;
    --bot)     bot_installed || bot_install_files; exec "$BOT_FILE" ;;
    "")        main_menu ;;
    *)         usage; exit 1 ;;
  esac
}

# Sourced with NLM_LIB=1 (by the Telegram bot) → expose functions, do not run.
if [[ "${NLM_LIB:-0}" != "1" ]]; then
  main "$@"
fi
