#!/bin/bash

# Script de déploiement automatisé Blue/Green v1
#
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO
# sudo ./Script_Installation_Blue_Green_v1.sh
#
# PRÉREQUIS:
# 1. Vous devez avoir ajouté une clé de déploiement (Deploy Key)
#    au dépôt GitHub pour l'utilisateur 'root' de ce serveur.

# --- Configuration ---
PROJECT_USER="vboxuser"
GIT_URL="git@github.com:Aquadrox/ADS_ReactDjango2.git"
PROJECT_SUBDIR="my_app" # Le sous-dossier de votre projet dans Git

# Chemins pour le déploiement Blue/Green
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"


# --- Contenu du fichier my_app.conf (mis à jour pour Blue/Green) ---
APACHE_CONFIG=$(cat <<EOF
<VirtualHost *:80>
    # --- 1. CONFIGURATION DE BASE ---
    # Le DocumentRoot pointe vers le LIEN SYMBOLIQUE
    DocumentRoot $LIVE_SYMLINK/$PROJECT_SUBDIR/frontend_app/build

    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/frontend_app/build>
        # Autorise Apache à suivre le lien symbolique
        Options +FollowSymLinks
        Require all granted
        AllowOverride All
        FallbackResource /index.html
    </Directory>


    # --- 2. ALIAS (Media, Static) ---
    Alias /media/ $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/media/
    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/media>
        Options +FollowSymLinks
        Require all granted
    </Directory>

    Alias /django-static/ $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/staticfiles/
    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/staticfiles>
        Options +FollowSymLinks
        Require all granted
    </Directory>


    # --- 3. CONFIGURATION WSGI (Backend Django) ---
    WSGIDaemonProcess django_app python-home=$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/.venv
    WSGIProcessGroup django_app
    WSGIScriptAlias /api $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py process-group=django_app application-group=%{GLOBAL}

    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core>
        Options +FollowSymLinks
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>


    # --- 4. LOGS ---
    ErrorLog \${APACHE_LOG_DIR}/my_app-error.log
    CustomLog \${APACHE_LOG_DIR}/my_app-access.log combined
</VirtualHost>
EOF
)

# --- Fonctions d'aide ---
msg_info() {
    echo -e "\n\e[34m--- $1 ---\e[0m"
}
msg_success() {
    echo -e "\e[32m✅ $1\e[0m"
}
msg_error() {
    echo -e "\e[31m❌ ERREUR: $1\e[0m" >&2
    exit 1
}

# --- Vérification initiale ---
if [ "$EUID" -ne 0 ]; then
    msg_error "Ce script doit être lancé avec sudo. Ex: sudo ./deploy.sh"
fi

set -e

# --- A. PRÉREQUIS SYSTÈME ---
msg_info "Mise à jour des paquets et installation des dépendances..."
apt-get update > /dev/null
apt-get install -y git apache2 libapache2-mod-wsgi-py3 python3-venv curl gpg pipx > /dev/null
pipx ensurepath # S'assure que pipx est dans le PATH de root
msg_success "Dépendances de base installées."

msg_info "Installation de Node.js et NPM (via NodeSource LTS)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
apt-get install -y nodejs > /dev/null
msg_success "Node.js et NPM installés."

# --- B. CLONAGE ET PERMISSIONS ---
msg_info "Préparation de SSH pour le clonage non-interactif..."
mkdir -p /root/.ssh
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null

msg_info "Nettoyage des anciennes installations..."
rm -rf "$BLUE_PATH" "$GREEN_PATH" "$LIVE_SYMLINK"

msg_info "Clonage du projet (via SSH) dans $BLUE_PATH..."
git clone "$GIT_URL" "$BLUE_PATH"

msg_info "Création du groupe 'webmasters' et ajout des utilisateurs..."
groupadd webmasters || true
usermod -aG webmasters "$PROJECT_USER"
usermod -aG webmasters www-data

msg_info "Application des permissions (chown, chmod, setgid)..."
# Correction du bug 'Permission denied' sur 'ln'
chgrp webmasters /var/www
chmod 775 /var/www

# Application des droits sur le dossier BLUE
chown -R "$PROJECT_USER:webmasters" "$BLUE_PATH"
find "$BLUE_PATH" -type d -exec chmod 775 {} \;
find "$BLUE_PATH" -type f -exec chmod 664 {} \;
find "$BLUE_PATH" -type d -exec chmod g+s {} \;
msg_success "Permissions pour BLUE configurées."

# --- C & D. INSTALLATION BACKEND & FRONTEND (sur BLUE) ---
msg_info "Création du sous-script d'installation (pour $PROJECT_USER)..."
SUB_SCRIPT_PATH="/home/$PROJECT_USER/install_sub.sh"

cat << EOF > "$SUB_SCRIPT_PATH"
#!/bin/bash
set -e # Arrête le sous-script en cas d'erreur

echo -e "\n--- [Sub-script] Démarrage en tant que \$(whoami) (avec les groupes: \$(id -Gn)) ---"

echo -e "\n--- [Sub-script] Installation/Mise à jour de Poetry... ---"
export PATH="\$HOME/.local/bin:\$PATH"
pipx install poetry > /dev/null
pipx ensurepath # S'assure que le .bashrc est à jour

# --- C. INSTALLATION BACKEND (sur BLUE) ---
echo -e "\n--- [Sub-script] Installation du Backend Django sur BLUE... ---"
cd "$BLUE_PATH/$PROJECT_SUBDIR/backend_project"
poetry config virtualenvs.in-project true
poetry install --only main

echo -e "\n--- [Sub-script] Lancement de collectstatic et migrate... ---"
poetry run python src/manage.py collectstatic --noinput
poetry run python src/manage.py migrate

# --- D. INSTALLATION FRONTEND (sur BLUE) ---
echo -e "\n--- [Sub-script] Installation du Frontend React sur BLUE... ---"
cd "$BLUE_PATH/$PROJECT_SUBDIR/frontend_app"
npm install
npm run build

echo -e "\n--- [Sub-script] Installation sur BLUE terminée avec succès. ---"
EOF

chmod +x "$SUB_SCRIPT_PATH"
chown "$PROJECT_USER:$PROJECT_USER" "$SUB_SCRIPT_PATH"

msg_info "Lancement du sous-script en tant que '$PROJECT_USER'..."
echo "****************************************************************"
echo ">>> VOUS DEVREZ ENTRER LE MOT DE PASSE POUR '$PROJECT_USER' <<<"
echo "****************************************************************"
su - "$PROJECT_USER" -c "$SUB_SCRIPT_PATH"

msg_success "Installation de l'environnement BLUE terminée."

# --- E. CRÉATION DE GREEN ET DU LIEN SYMBOLIQUE ---
msg_info "Création de l'environnement GREEN (par copie de BLUE)..."
cp -r "$BLUE_PATH" "$GREEN_PATH"

msg_info "Vérification des permissions sur GREEN..."
chown -R "$PROJECT_USER:webmasters" "$GREEN_PATH"
find "$GREEN_PATH" -type d -exec chmod 775 {} \;
find "$GREEN_PATH" -type f -exec chmod 664 {} \;
find "$GREEN_PATH" -type d -exec chmod g+s {} \;
msg_success "Permissions pour GREEN configurées."

msg_info "Création du lien symbolique LIVE (pointant vers BLUE)..."
ln -sfn "$BLUE_PATH" "$LIVE_SYMLINK"
chown -h "$PROJECT_USER:webmasters" "$LIVE_SYMLINK"
msg_success "Lien symbolique LIVE créé."

# --- F. CONFIGURATION ET DÉMARRAGE APACHE ---
msg_info "Création du fichier de configuration Apache..."
echo "$APACHE_CONFIG" > /etc/apache2/sites-available/my_app.conf

msg_info "Activation du site 'my_app'..."
a2dissite 000-default.conf || true
a2ensite my_app.conf || true

msg_info "Test de la configuration Apache..."
apache2ctl configtest

msg_info "Redémarrage d'Apache..."
systemctl restart apache2

# --- G. CONCLUSION ---
msg_success "Déploiement Blue/Green initial terminé !"
echo "Votre site devrait être accessible à http://<votre_ip>"
echo "LIVE pointe actuellement sur BLUE."
msg_info "En cas d'erreur 500, vérifiez les logs avec :"
echo "sudo tail -f /var/log/apache2/my_app-error.log"

# Nettoyage
rm "$SUB_SCRIPT_PATH"
