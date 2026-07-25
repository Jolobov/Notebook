### Homepage

Homepage — это современная, полностью статическая, быстрая и надежно защищенная панель для ваших приложений. Она легко настраивается с помощью YAML-файлов и поддерживает интеграцию с более чем 100 сервисами, а также переводы на несколько языков. Благодаря тому, что все запросы к API проходят через прокси-сервер, ваши ключи API остаются в безопасности и никогда не доступны на стороне клиента.

*   **Порт по умолчанию:** `3000`
*   **Лицензия:** [GNU General Public License v3.0](https://github.com/gethomepage/homepage/blob/main/LICENSE)

[Подробнее о проекте Homepage](https://gethomepage.dev/)

**Конфигурация:**
```yaml
services:
  homepage:
    image: ghcr.io/gethomepage/homepage:latest
    container_name: homepage
    restart: unless-stopped
    volumes:
      - config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock
    networks:
      - default
      - proxy-network

volumes:
  config:

networks:
  proxy-network:
    external: true
