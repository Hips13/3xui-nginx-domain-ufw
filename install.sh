#!/bin/bash

# === Цвета ===
RED="\e[31m"; GREEN="\e[32m"; YELLOW="\e[33m"; BLUE="\e[34m"; CYAN="\e[36m"; RESET="\e[0m"

clear
echo -e "${CYAN}Проверка root...${RESET}"
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}Ошибка: скрипт должен быть запущен от root.${RESET}"
    exit 1
fi

# === Получить внешний IP-адрес сервера ===
SERVER_IP=$(curl -s https://api.ipify.org)
echo -e "${GREEN}Внешний IP-адрес сервера: ${SERVER_IP}${RESET}"

# === Получить домен ===
echo -e "${YELLOW}Введите доменное имя (hostname) для SSL (например, sub.example.com):${RESET}"
read -r DOMAIN

# === Генерация случайного SSH порта ===
SSH_PORT=$(shuf -i 20000-60000 -n 1)

# === Спросить про безопасность ===
echo -e "\n${YELLOW}Установить безопасность? (Введите номер)${RESET}"
echo -e "1. ${GREEN}SSH${RESET} (Смена порта, установка ключа)"
echo -e "2. ${GREEN}SSH + UFW${RESET} (Пункт 1 + Фаервол)"
echo -e "3. ${GREEN}SSH + UFW + Спрятать панель${RESET} (Пункт 2 + Панель доступна только через SSH-тоннель)"
echo -e "4. ${RED}Игнорировать безопасность${RESET} (Не рекомендуется!)"
read -r SECURITY_LEVEL

# === Установка SSH безопасности (Уровни 1, 2, 3) ===
if [[ "$SECURITY_LEVEL" == "1" || "$SECURITY_LEVEL" == "2" || "$SECURITY_LEVEL" == "3" ]]; then
    echo -e "${CYAN}Настраиваю SSH...${RESET}"
    
    # Комментируем Include
    sed -i 's/^Include/#Include/g' /etc/ssh/sshd_config

    # Меняем порт
    sed -i "s/^#Port .*/Port $SSH_PORT/; s/^Port [0-9]*/Port $SSH_PORT/" /etc/ssh/sshd_config

    # Включить ключи, отключить пароль
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config

    echo -e "${YELLOW}Введите ваш SSH public key:${RESET}"
    read -r SSH_KEY
    mkdir -p /root/.ssh
    echo "$SSH_KEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys

    systemctl reload ssh || true
    systemctl reload sshd || true

    echo -e "${GREEN}SSH настроен${RESET}"
fi

---

# === Установка 3x-ui и извлечение данных ===
echo -e "${CYAN}Устанавливаю 3x-ui...${RESET}"
PANEL_OUTPUT=$(printf 'n' | bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh))

echo -e "$PANEL_OUTPUT" | grep -E 'Username|Password|Port|WebBasePath|Access URL'
echo -e "${GREEN}------------------------------------------${RESET}"

# === Автоматическое извлечение данных панели ===
LOGIN_INFO=$(echo -e "$PANEL_OUTPUT" | grep -E 'Username|Password')
LOGIN=$(echo -e "$PANEL_OUTPUT" | grep 'Username:' | awk '{print $2}' | tr -d '\r')
PASS=$(echo -e "$PANEL_OUTPUT" | grep 'Password:' | awk '{print $2}' | tr -d '\r')
PANEL_PORT=$(echo -e "$PANEL_OUTPUT" | grep 'Port:' | awk '{print $2}' | tr -d '\r')
BASEPATH=$(echo -e "$PANEL_OUTPUT" | grep 'WebBasePath:' | awk '{print $2}' | tr -d '\r')

if [ -z "$PANEL_PORT" ] || [ -z "$BASEPATH" ]; then
    echo -e "${RED}Ошибка: Не удалось автоматически извлечь Port или WebBasePath.${RESET}"
    echo -e "${YELLOW}Пожалуйста, введите их вручную, используя данные выше!${RESET}"
    echo -e "${YELLOW}Введите порт панели (Port):${RESET}"
    read -r PANEL_PORT
    echo -e "${YELLOW}Введите WebBasePath панели (без слэша в начале):${RESET}"
    read -r BASEPATH
fi

# Удаляем начальный слеш из BASEPATH, если он есть, чтобы корректно формировать URL
BASEPATH=$(echo "$BASEPATH" | sed 's/^\///')

echo -e "${GREEN}Автоматически определены параметры:${RESET}"
echo -e "${GREEN}Порт панели: $PANEL_PORT${RESET}"
echo -e "${GREEN}WebBasePath: $BASEPATH${RESET}"
echo -e "${YELLOW}Нажмите Enter для продолжения...${RESET}"
read

# --- ГЕНЕРАЦИЯ ПАРАМЕТРОВ ПОДПИСКИ (СКРЫТА ОТ ПОЛЬЗОВАТЕЛЯ) ---
SUB_PORT=$(shuf -i 20000-60000 -n 1)
SUB_PATH="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)/"

# === Первичная настройка 3x-ui: SSL и BBR ===
echo -e "${CYAN}Первичная настройка 3x-ui: Запускаю автоматическую установку SSL и BBR...${RESET}"

# 1. Установка SSL (18, 1, domain, 80, y, 1, y, enter, 0, 0)
# 2. Активация BBR (23, 1, 0, 0)
(
    # Установка SSL
    printf '18\n1\n%s\n80\ny\n1\ny\n\n0\n' "$DOMAIN"
    # Активация BBR
    printf '23\n1\n0\n'
    # Выход из главного меню
    printf '0\n'
) | x-ui

echo -e "${GREEN}Настройка SSL и BBR завершена${RESET}"
echo -e "${YELLOW}Нажмите Enter для продолжения...${RESET}"
read

# ---

# === Установка nginx ===
echo -e "${CYAN}Обновляю список пакетов и устанавливаю nginx...${RESET}"
apt update && apt install -y nginx

# === Настройка nginx ===
# Направляем порт 80 на localhost:8080 для Fallback (V2ray/Xray)
sed -i 's/listen 80 default_server;/listen 127.0.0.1:8080 default_server;/' /etc/nginx/sites-enabled/default
sed -i '/listen \[::\]:80 default_server;/d' /etc/nginx/sites-enabled/default

# Добавляем файл-заглушку
wget wget https://raw.githubusercontent.com/Hips13/3xui-nginx-domain-ufw/main/site/index.html -O /var/www/html/index.html
systemctl reload nginx

# ---

# === Инструкции пользователю (Ручная настройка Inbound) ===
echo -e "\n${CYAN}--- ИНСТРУКЦИИ ДЛЯ РУЧНОЙ НАСТРОЙКИ 3X-UI ---${RESET}"

# Общая информация для всех уровней, где используется домен
PANEL_URL="${YELLOW}https://${DOMAIN}:${PANEL_PORT}/${BASEPATH}/${RESET}"
PANEL_LOGIN_INFO="${GREEN}Логин: ${YELLOW}${LOGIN}${RESET} | ${GREEN}Пароль: ${YELLOW}${PASS}${RESET}"

# Блок инструкций для уровней 1, 2
if [[ "$SECURITY_LEVEL" == "1" || "$SECURITY_LEVEL" == "2" ]]; then
    echo -e "${GREEN}Ссылка на панель: ${PANEL_URL}"
    echo -e "${PANEL_LOGIN_INFO}"
    
    echo -e "\n1. ${GREEN}Включить подписки и задать${RESET} (удобно, но страдает маскировка). ${BLUE}Настройки -> Подписки:${RESET}"
    echo -e "    - Порт подписки: ${YELLOW}${SUB_PORT}${RESET}"
    echo -e "    - Корневой путь: ${YELLOW}${SUB_PATH}${RESET}"
    
    echo -e "\n2. ${GREEN}Создать инбаунд с параметрами:${RESET}"
    echo -e "    - Порт: ${YELLOW}443${RESET}"
    echo -e "    - Безопасность: ${YELLOW}TLS${RESET}"
    echo -e "    - ALPN: оставить только ${YELLOW}http/1.1${RESET}"
    echo -e "    - Установить ${YELLOW}сертификат панели${RESET}"
    echo -e "    - Добавить Fallbacks: Dest: ${YELLOW}8080${RESET}"
    echo -e "    - Добавить первого клиента (email - понятное название на английском без пробелов)"
    echo -e "    - Всем клиентам устанавливать Flow: ${YELLOW}xtls-rprx-vision${RESET}"

# Блок инструкций для уровня 3
elif [[ "$SECURITY_LEVEL" == "3" ]]; then
    echo -e "${RED}Уровень безопасности 3: Панель будет скрыта!${RESET}"
    echo -e "${GREEN}Ссылка на панель: ${PANEL_URL}"
    echo -e "${PANEL_LOGIN_INFO}"
    
    echo -e "\n1. ${RED}!!!КРАЙНЕ НЕ РЕКОМЕНДУЕТСЯ!!! Включить подписки и задать${RESET} (удобно, но страдает маскировка). ${BLUE}Настройки -> Подписки:${RESET}"
    echo -e "    - Порт подписки: ${YELLOW}${SUB_PORT}${RESET}"
    echo -e "    - Корневой путь: ${YELLOW}${SUB_PATH}${RESET}"
    
    echo -e "\n2. ${GREEN}Создать инбаунд с параметрами:${RESET}"
    echo -e "    - Порт: ${YELLOW}443${RESET}"
    echo -e "    - Безопасность: ${YELLOW}TLS${RESET}"
    echo -e "    - ALPN: оставить только ${YELLOW}http/1.1${RESET}"
    echo -e "    - Установить ${YELLOW}сертификат панели${RESET}"
    echo -e "    - Добавить Fallbacks: Dest: ${YELLOW}8080${RESET}"
    echo -e "    - Добавить первого клиента (email - понятное название на английском без пробелов)"
    echo -e "    - Всем клиентам устанавливать Flow: ${YELLOW}xtls-rprx-vision${RESET}"

    echo -e "\n3. ${RED}Закрыть панель из вне !!!ДЕЛАТЬ В ПОСЛЕДНЮЮ ОЧЕРЕДЬ, доступ к панели пропадет!!! ${BLUE}Настройки -> Панель:${RESET}"
    echo -e "    - IP-адрес для управления панелью: ${YELLOW}127.0.0.1${RESET}"
    
# Блок инструкций для уровня 4
elif [[ "$SECURITY_LEVEL" == "4" ]]; then
    echo -e "${RED}Уровень безопасности 4: Настройка без защиты!${RESET}"
    
    echo -e "\n1. ${GREEN}Включить подписки и задать (если нужны). ${BLUE}Настройки -> Подписки:${RESET}"
    echo -e "    - Порт подписки: ${YELLOW}${SUB_PORT}${RESET}"
    echo -e "    - Корневой путь: ${YELLOW}${SUB_PATH}${RESET}"
    
    echo -e "\n2. ${GREEN}Создать инбаунд с параметрами:${RESET}"
    echo -e "    - Порт: ${YELLOW}443${RESET}"
    echo -e "    - Безопасность: ${YELLOW}TLS${RESET}"
    echo -e "    - ALPN: оставить только ${YELLOW}http/1.1${RESET}"
    echo -e "    - Установить ${YELLOW}сертификат панели${RESET}"
    echo -e "    - Добавить Fallbacks: Dest: ${YELLOW}8080${RESET}"
    echo -e "    - Добавить первого клиента (email - понятное название на английском без пробелов)"
    echo -e "    - Всем клиентам устанавливать Flow: ${YELLOW}xtls-rprx-vision${RESET}"
fi

echo -e "\n${YELLOW}Нажмите Enter когда завершите ручную настройку в панели 3x-ui...${RESET}"
read

# === Вопрос о подписках для UFW ===
SUBSCRIPTION_ENABLED="n"
if [[ "$SECURITY_LEVEL" == "2" || "$SECURITY_LEVEL" == "3" || "$SECURITY_LEVEL" == "4" ]]; then
    echo -e "${YELLOW}Вы включили подписки в настройках панели 3x-ui (Порт: ${SUB_PORT})? (y/n)${RESET}"
    read -r SUBSCRIPTION_ENABLED
fi

# ---

# === Проверка и установка UFW (Уровни 2, 3) ===
if [[ "$SECURITY_LEVEL" == "2" || "$SECURITY_LEVEL" == "3" ]]; then
    
    # ПРОВЕРКА И УСТАНОВКА UFW
    if ! command -v ufw &> /dev/null
    then
        echo -e "${CYAN}UFW не найден. Устанавливаю UFW...${RESET}"
        apt update && apt install ufw -y
    fi
    
    echo -e "${CYAN}Настраиваю UFW...${RESET}"

    # Добавляем разрешения перед включением UFW
    ufw allow ${SSH_PORT}/tcp # Всегда открыт для SSH
    
    # Открываем порт панели только для уровня 2
    if [[ "$SECURITY_LEVEL" == "2" ]]; then
        ufw allow ${PANEL_PORT}/tcp
    fi
    
    # Добавляем правило для порта подписки, если пользователь подтвердил его включение
    if [[ "$SUBSCRIPTION_ENABLED" =~ ^[Yy]$ ]]; then
        ufw allow ${SUB_PORT}/tcp
        echo -e "${GREEN}Добавлено правило UFW для порта подписки: ${SUB_PORT}/tcp${RESET}"
    fi

    ufw allow 443/tcp
    ufw allow 80/tcp 

    # ИЗМЕНЕНИЯ В before.rules (ИСПРАВЛЕНИЕ ОШИБКИ iptables-restore)
    echo -e "${CYAN}Настраиваю /etc/ufw/before.rules (отключаю ICMP-Flooding)...${RESET}"
    
    ICMP_RULES=$(cat << EOF
# ok icmp codes for INPUT
-A ufw-before-input -p icmp --icmp-type destination-unreachable -j DROP
-A ufw-before-input -p icmp --icmp-type time-exceeded -j DROP
-A ufw-before-input -p icmp --icmp-type parameter-problem -j DROP
-A ufw-before-input -p icmp --icmp-type echo-request -j DROP
-A ufw-before-input -p icmp --icmp-type source-quench -j DROP

# ok icmp code for FORWARD
-A ufw-before-forward -p icmp --icmp-type destination-unreachable -j DROP
-A ufw-before-forward -p icmp --icmp-type time-exceeded -j DROP
-A ufw-before-forward -p icmp --icmp-type parameter-problem -j DROP
-A ufw-before-forward -p icmp --icmp-type echo-request -j DROP
EOF
)
    # Удаляем предыдущие строки, если они были добавлены некорректно
    sed -i '/-A ufw-before-input -p icmp/d' /etc/ufw/before.rules
    sed -i '/-A ufw-before-forward -p icmp/d' /etc/ufw/before.rules
    
    # Добавляем правила перед командой COMMIT
    # Вставляем правила перед последней строкой COMMIT
    sed -i "/^COMMIT/i $ICMP_RULES" /etc/ufw/before.rules

    ufw --force enable
    ufw reload # Применяем изменения в before.rules
    echo -e "${GREEN}UFW настроен и включен.${RESET}"
fi

# ---

# === Cron fix ===
echo -e "${CYAN}Применяю фикс для обновления сертификатов ACME.SH через Cron...${RESET}"
# Используем $DOMAIN в команде cron для явного указания домена при обновлении
CRON_COMMAND="52 9 * * * ufw allow 80/tcp && \"/root/.acme.sh\"/acme.sh --cron --home \"/root/.acme.sh\" -d $DOMAIN > /dev/null && ufw deny 80/tcp"
# Удаляем старую строку cron и добавляем новую, чтобы избежать дублирования
(crontab -l 2>/dev/null | grep -v 'acme.sh --cron'; echo "$CRON_COMMAND") | crontab -

echo -e "${GREEN}Cron-задача обновлена.${RESET}"

# ---

# === Заключительные инструкции ===
clear
echo -e "${CYAN}--- ЗАКЛЮЧИТЕЛЬНАЯ ИНФОРМАЦИЯ ---${RESET}"
echo -e "\n${GREEN}Для подключения к серверу (через SSH-ключ):${RESET}"
echo -e "${YELLOW}ssh root@${SERVER_IP} -p ${SSH_PORT} -i \"C:/users/пользователь/.ssh/<key>\"${RESET}"
echo -e "\n---"

# Логика для уровней 1 и 2 (Прямой доступ)
if [[ "$SECURITY_LEVEL" == "1" || "$SECURITY_LEVEL" == "2" ]]; then
    echo -e "${GREEN}Уровень безопасности: SSH / SSH + UFW${RESET}"
    echo -e "${GREEN}Панель доступна напрямую.${RESET}"
    
    echo -e "\n${GREEN}Данные панели:${RESET}"
    echo -e "$LOGIN_INFO"
    echo -e "${GREEN}Адрес панели: ${PANEL_URL}"

# Логика для уровня 3 (Скрытая панель)
elif [[ "$SECURITY_LEVEL" == "3" ]]; then
    echo -e "${RED}Уровень безопасности: SSH + UFW + Спрятать панель${RESET}"
    echo -e "${RED}Доступ к панели можно получить только через SSH-тоннель.${RESET}"
    
    echo -e "\n${RED}!!! ВАЖНО ДЛЯ КЛИЕНТОВ !!!${RESET}"
    echo -e "${RED}При создании конфигов и подписок обязательно в настройках клиента изменить 127.0.0.1 на ваш домен (${DOMAIN}).${RESET}"
    
    echo -e "\n${GREEN}Для открытия тоннеля в терминале (команда для Windows/Linux/macOS):${RESET}"
    echo -e "${YELLOW}ssh -L ${PANEL_PORT}:127.0.0.1:${PANEL_PORT} root@${SERVER_IP} -p ${SSH_PORT} -i \"C:/users/пользователь/.ssh/<key>\"${RESET}"
    
    echo -e "\n${GREEN}В браузере (при открытом тоннеле):${RESET}"
    echo -e "${YELLOW}https://127.0.0.1:${PANEL_PORT}/${BASEPATH}/${RESET}"
    
    echo -e "\n${GREEN}Данные панели:${RESET}"
    echo -e "$LOGIN_INFO"
    
# Логика для уровня 4 (Игнорирована безопасность)
elif [[ "$SECURITY_LEVEL" == "4" ]]; then
    echo -e "${RED}Уровень безопасности: Игнорирован${RESET}"
    echo -e "${RED}Ваша панель доступна по стандартному порту и небезопасна.${RESET}"
    
    echo -e "\n${RED}Данные панели (КРАЙНЕ РЕКОМЕНДУЕТСЯ СМЕНИТЬ ПАРОЛЬ!):${RESET}"
    echo -e "$LOGIN_INFO"
    echo -e "${RED}Адрес панели: https://${SERVER_IP}:${PANEL_PORT}/${BASEPATH}/${RESET}"
fi

echo -e "\n${RED}!!!ЗАПИШИТЕ ДАННЫЕ!!!${RESET}"
echo -e "\n${RED}Для применения настроек необходима перезагрузка сервера${RESET}"
echo -e "\n${CYAN}Для перезагрузки сервера нажмите ENTER${RESET}"

echo -e "\n${GREEN}Готово!${RESET}"
