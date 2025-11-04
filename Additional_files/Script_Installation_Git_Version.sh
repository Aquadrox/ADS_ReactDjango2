#!/bin/bash

# Script de déploiement automatisé v5 (corrigé)
#
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO
# sudo ./Script_Installation_v5.sh
#
# PRÉREQUIS:
# 1. Vous devez avoir ajouté une clé de déploiement (Deploy Key)
#    au dépôt GitHub pour l'utilisateur 'root' de ce serveur.

# --- Configuration ---
PROJECT_USER="vboxuser"
GIT_URL="git@github.com:Aquadrox/ADS_ReactDjango2.git"
REPO_ROOT="/var/www/ADS_ReactDjango2"
PROJECT_PATH="$REPO_ROOT/my_app"

# --- Contenu du fichier my_app.conf ---
APACHE_CONFIG=$(cat <<EOF
#/etc/apache2/sites-available/my_app.conf
<VirtualHost *:80>
    DocumentRoot $PROJECT_PATH/frontend_app/build
    <Directory $PROJECT_PATH/frontend_app/build>
        Require all granted
        AllowOverride All
        FallbackResource /index.html
    </Directory>

    Alias /media/ $PROJECT_PATH/backend_project/src/media/
    <Directory $PROJECT_PATH/backend_project/src/media>
        Require all granted
    </Directory>

    Alias /django-static/ $PROJECT_PATH/backend_project/src/staticfiles/
    <Directory $PROJECT_PATH/backend_project/src/staticfiles>
        Require all granted
    </Directory>

    WSGIDaemonProcess django_app python-home=$PROJECT_PATH/backend_project/.venv
    WSGIProcessGroup django_app
    WSGIScriptAlias /api $PROJECT_PATH/backend_project/src/core/wsgi.py process-group=django_app application-group=%{GLOBAL}

    <Directory $PROJECT_PATH/backend_project/src/core>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

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
msg_success "Dépendances de base installées."

msg_info "Installation de Node.js et NPM (via NodeSource LTS)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
apt-get install -y nodejs > /dev/null
msg_success "Node.js et NPM installés."

# --- B. CLONAGE ET PERMISSIONS ---
msg_info "Préparation de SSH pour le clonage non-interactif..."
mkdir -p /root/.ssh
ssh-keyscan github.com >> /root/.ssh/known_hosts

msg_info "Clonage du projet (via SSH) vers $REPO_ROOT..."
rm -rf "$REPO_ROOT"
git clone "$GIT_URL" "$REPO_ROOT"

msg_info "Création du groupe 'webmasters' et ajout des utilisateurs..."
groupadd webmasters || true
usermod -aG webmasters "$PROJECT_USER"
usermod -aG webmasters www-data

msg_info "Application des permissions (chown, chmod, setgid) sur $REPO_ROOT..."
chown -R "$PROJECT_USER:webmasters" "$REPO_ROOT"
find "$REPO_ROOT" -type d -exec chmod 775 {} \;
find "$REPO_ROOT" -type f -exec chmod 664 {} \;
find "$REPO_ROOT" -type d -exec chmod g+s {} \;
msg_success "Permissions configurées."

# --- C & D. INSTALLATION BACKEND & FRONTEND (via sous-script) ---
msg_info "Création du sous-script d'installation..."
#
# !! MODIFICATION !! Utilisation du dossier $HOME de l'utilisateur au lieu de /tmp
#
SUB_SCRIPT_PATH="/home/$PROJECT_USER/install_sub.sh"
#
# !! FIN MODIFICATION !!
#

cat << EOF > "$SUB_SCRIPT_PATH"
#!/bin/bash
set -e # Arrête le sous-script en cas d'erreur

echo -e "\n--- [Sub-script] Démarrage en tant que \$(whoami) (avec les groupes: \$(id -Gn)) ---"

# !! CORRIGÉ !! Installation de Poetry par le bon utilisateur
echo -e "\n--- [Sub-script] Installation/Mise à jour de Poetry... ---"
pipx install poetry > /dev/null
export PATH="\$HOME/.local/bin:\$PATH"
pipx ensurepath # S'assure que le .bashrc est à jour

# --- C. INSTALLATION BACKEND ---
echo -e "\n--- [Sub-script] Installation du Backend Django... ---"
cd "$PROJECT_PATH/backend_project"
poetry config virtualenvs.in-project true
poetry install --only main

echo -e "\n--- [Sub-script] Lancement de collectstatic et migrate... ---"
poetry run python src/manage.py collectstatic --noinput
poetry run python src/manage.py migrate

# --- D. INSTALLATION FRONTEND ---
echo -e "\n--- [Sub-script] Installation du Frontend React... ---"
cd "$PROJECT_PATH/frontend_app"
npm install
npm run build

echo -e "\n--- [Sub-script] Installation terminée avec succès. ---"
EOF

chmod +x "$SUB_SCRIPT_PATH"
chown "$PROJECT_USER:$PROJECT_USER" "$SUB_SCRIPT_PATH"

msg_info "Lancement du sous-script en tant que '$PROJECT_USER'..."
echo "****************************************************************"
echo ">>> VOUS DEVREZ ENTRER LE MOT DE PASSE POUR '$PROJECT_USER' <<<"
echo "****************************************************************"
su - "$PROJECT_USER" -c "$SUB_SCRIPT_PATH"

msg_success "Installation Backend et Frontend terminée."

# --- E. CONFIGURATION ET DÉMARRAGE APACHE ---
msg_info "Création du fichier de configuration Apache..."
echo "$APACHE_CONFIG" > /etc/apache2/sites-available/my_app.conf

msg_info "Activation du site 'my_app'..."
a2dissite 000-default.conf || true
a2ensite my_app.conf || true

msg_info "Test de la configuration Apache..."
apache2ctl configtest

msg_info "Redémarrage d'Apache..."
systemctl restart apache2

# --- F. CONCLUSION ---
msg_success "Déploiement terminé !"
echo "Votre site devrait être accessible à http://<votre_ip>"
msg_info "En cas d'erreur 500, vérifiez les logs avec :"
echo "sudo tail -f /var/log/apache2/my_app-error.log"

# Nettoyage
rm "$SUB_SCRIPT_PATH"
