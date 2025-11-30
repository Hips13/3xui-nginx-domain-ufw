# 3xui-nginx-domain-ufw

Скрипт установки 
```bash
bash <(curl -Ls https://raw.githubusercontent.com/Hips13/3xui-nginx-domain-ufw/main/install.sh)
```

Отдельно страница
```bash
wget https://raw.githubusercontent.com/Hips13/3xui-nginx-domain-ufw/main/site/index.html -O /var/www/html/index.html
```


# Подключение к серверу по имени
```bash
New-Item -Path $HOME\.ssh\config -ItemType File
```
```bash
Notepad $HOME\.ssh\config
```
```bash
Host server_name
  HostName ip_server
  StrictHostKeyChecking no
  User user_name
  ForwardAgent yes
  IdentityFile ~/.ssh/ssh_key
  IdentitiesOnly yes
  AddKeysToAgent yes
  ServerAliveInterval 60
  ServerAliveCountMax 1200
  PORT 12345
```
```bash
ssh server_name
```
