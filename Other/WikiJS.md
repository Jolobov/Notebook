### Wiki.js

Wiki.js — это мощная и расширяемая вики-система с открытым исходным кодом, созданная на Node.js. Она позволяет легко создавать документацию благодаря интуитивно понятному интерфейсу. Wiki.js работает практически на любой платформе и совместима с различными базами данных, такими как PostgreSQL, MySQL, MariaDB, MS SQL Server и SQLite. Вы можете полностью настроить внешний вид вашей вики, включая светлый и темный режимы.

*   **Порт по умолчанию:** `3000`
*   **Лицензия:** [GNU Affero General Public License v3.0](https://github.com/requarks/wiki/blob/main/LICENSE)

[Подробнее о проекте Wiki.js](https://js.wiki/)

**Конфигурация:**
```yaml
services:
  db:
    image: postgres:15-alpine
    container_name: wiki-db
    environment:
      POSTGRES_DB: wiki
      POSTGRES_USER: wikijs
      POSTGRES_PASSWORD: #ВАШ ПАРОЛЬ#
    logging:
      driver: none
    restart: unless-stopped
    volumes:
      - db_data:/var/lib/postgresql/data
    networks:
      - default

  wiki:
    image: ghcr.io/requarks/wiki:2
    container_name: wiki
    depends_on:
      - db
    environment:
      DB_TYPE: postgres
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: wikijs
      DB_PASS: #ВАШ ПАРОЛЬ#
      DB_NAME: wiki
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
