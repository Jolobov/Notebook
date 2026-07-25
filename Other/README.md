# Документация по Docker и Docker Compose

**Docker** — это открытая платформа для разработки, доставки и запуска приложений в контейнерах. Контейнеры позволяют упаковать приложение со всеми его зависимостями в один объект, который можно запустить на любой системе с поддержкой Docker. Это значительно упрощает развертывание приложений и обеспечивает их стабильную работу в различных средах.

**Docker Compose** — это инструмент для определения и запуска многоконтейнерных приложений Docker. Он использует YAML-файл для настройки служб вашего приложения, что позволяет запускать и останавливать все необходимые контейнеры одной командой.

## Установка Docker и Docker Compose

### Установка Docker Engine

1.  **Обновите существующий список пакетов:**
    ```bash
    sudo apt update
    ```

2.  **Установите необходимые пакеты, которые позволяют `apt` использовать репозитории по HTTPS:**
    ```bash
    sudo apt install apt-transport-https ca-certificates curl gnupg2 software-properties-common
    ```

3.  **Добавьте официальный GPG-ключ Docker в вашу систему:**
    ```bash
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg
    ```

4.  **Добавьте репозиторий Docker в источники APT:**
    ```bash
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    ```

5.  **Обновите базу данных пакетов с пакетами Docker из недавно добавленного репозитория:**
    ```bash
    sudo apt update
    ```

6.  **Установите Docker Engine, CLI и плагин Compose:**
    ```bash
    sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    ```

7.  **Убедитесь, что Docker установлен правильно, запустив образ `hello-world`:**
    ```bash
    sudo docker run hello-world
    ```
### Проверка установки Docker Compose

Проверьте, что плагин Docker Compose успешно установлен, выполнив команду:
```bash
docker compose version
