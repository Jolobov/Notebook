### Uptime Kuma

Uptime Kuma — это простой в использовании инструмент для мониторинга времени безотказной работы, который вы можете разместить на собственном сервере. Он позволяет отслеживать доступность различных сервисов по HTTP/HTTPS, TCP-портам, а также проверять DNS-записи и контейнеры Docker. Uptime Kuma предлагает красивый, реактивный и быстрый пользовательский интерфейс с поддержкой темного режима.

*   **Порт по умолчанию:** `3001`
*   **Лицензия:** [MIT License](https://github.com/louislam/uptime-kuma/blob/master/LICENSE)

[Подробнее о проекте Uptime Kuma](https://github.com/louislam/uptime-kuma)

**Конфигурация:**
```yaml
services:
  db:
    image: postgres:15-alpine
    container_name: uptime-kuma-db
    environment:
      POSTGRES_DB: uptime
      POSTGRES_USER: uptime_kuma
      POSTGRES_PASSWORD: #ВАШ ПАРОЛЬ#
    logging:
      driver: none
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - default

  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    depends_on:
      - db
    environment:
      DB_TYPE: postgres
      DB_HOST: db
      DB_USER: uptime_kuma
      DB_PASS: #ВАШ ПАРОЛЬ#
      DB_NAME: uptime
    restart: unless-stopped
    networks:
      - default
      - proxy-network

volumes:
  db_data:

networks:
  proxy-network:
    external: true
```
