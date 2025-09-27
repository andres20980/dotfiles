# Mi Configuración de WSL (Dotfiles)

Este repositorio contiene la configuración de mi entorno de desarrollo en WSL (Ubuntu). Incluye la configuración de `zsh`, `Oh My Zsh`, `nvm`, y otros.

También incluye un script (`install.sh`) para automatizar la instalación de todas las herramientas.

## 🚀 Cómo restaurar la configuración en una máquina nueva

1.  **Clonar este repositorio:**
    ```bash
    # Clona el repositorio en tu directorio home
    git clone https://github.com/andres20980/dotfiles.git ~/dotfiles
    ```

2.  **Ejecutar el script de instalación:**
    Este script instalará todas las aplicaciones, herramientas y configuraciones necesarias.
    ```bash
    # Navega a la carpeta
    cd ~/dotfiles

    # Dale permisos de ejecución y lánzalo
    chmod +x install.sh
    ./install.sh
    ```
    *Nota: El script usará `sudo`, por lo que te pedirá tu contraseña.*

3.  **Crear el enlace simbólico:**
    El script no sobreescribe tu `.zshrc` por seguridad. Después de que el script termine, enlaza el `.zshrc` de este repositorio a tu `home`.
    ```bash
    # Borra el .zshrc por defecto si existe
    rm ~/.zshrc

    # Crea el enlace simbólico
    ln -s ~/dotfiles/.zshrc ~/.zshrc
    ```

4.  **Configurar tu identidad de Git:**
    El script no configura tus datos personales. Hazlo con los siguientes comandos:
    ```bash
    git config --global user.name "tu-nombre"
    git config --global user.email "tu-email@example.com"
    ```

5.  **Reiniciar la Terminal:**
    Cierra y vuelve a abrir la terminal para que todos los cambios (`zsh`, `nvm`, etc.) se carguen correctamente.

6.  **Autenticar Git con GitHub:**
    La primera vez que hagas `git push` a un repositorio privado, el Git Credential Manager (instalado por el script) te pedirá que te autentiques en GitHub a través de tu navegador o con un Token de Acceso Personal (PAT). Solo tendrás que hacerlo una vez.

¡Y listo! Tu entorno estará replicado.

# Prueba final de GCM
