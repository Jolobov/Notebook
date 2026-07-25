### Portainer

Portainer — это универсальная платформа для управления контейнерами, которая упрощает развертывание, устранение неполадок и обеспечение безопасности в средах Kubernetes, Docker и Podman. Portainer предоставляет удобный графический интерфейс, который позволяет управлять всеми вашими ресурсами оркестрации (контейнерами, образами, томами, сетями и многим другим). Он подходит для развертывания как в облаке, так и локально, и не требует изменения вашей текущей инфраструктуры.

*   **Порты по умолчанию:** `9443` (HTTPS), `9000` (HTTP), `8000` (Edge Agent)
*   **Лицензия:** [zlib License](https://github.com/portainer/portainer/blob/develop/LICENSE)

[Подробнее о проекте Portainer](https://www.portainer.io/)

**Команда для развертывания:**
```Bash
docker run -d \
-p 8000:8000 \
-p 9000:9000 \
--name=portainer \
--restart=always \
-v /var/run/docker.sock:/var/run/docker.sock \
-v portainer_data:/data \
portainer/portainer-ce:latest
```
