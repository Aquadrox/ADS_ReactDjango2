#!/bin/bash

# Script de déploiement automatisé Blue/Green v1
#
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO
# sudo ./Script_Installation_Blue_Green_v1.sh

# --- Configuration ---
PROJECT_USER="vboxuser"
GIT_URL="git@github.com:Aquadrox/ADS_ReactDjango2.git"
PROJECT_SUBDIR="my_app"
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"

# --- Configuration du Logging ---
LOG_FILE="my_app_deployment.log"
SCRIPT_NAME="INSTALL"
# S'assure que le fichier log existe et est inscriptible
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# --- Fonctions de Logging ---
# Niveaux: STEP, SUCCESS, ERROR, WARN, INFO, DEBUG
log_msg() {
    local LEVEL=$1
    local STEP_TAG=$2
    local MESSAGE=$3
    local TIMESTAMP=$(date --iso-8601=seconds)
    local LOG_ENTRY="[$TIMESTAMP] [$SCRIPT_NAME] [$LEVEL] [$STEP_TAG] :: $MESSAGE"

    echo "$LOG_ENTRY" >> "$LOG_FILE"

    case "$LEVEL" in
        "STEP")
            echo -e "\n\e[34m--- [$STEP_TAG] $MESSAGE ---\e[0m"
            ;;
        "SUCCESS")
            echo -e "\e[32m✅ [$STEP_TAG] $MESSAGE\e[0m"
            ;;
        "ERROR")
            echo -e "\e[31m❌ ERREUR [$STEP_TAG]: $MESSAGE\e[0m" >&2
            ;;
        "WARN")
            echo -e "\e[33m⚠️ AVIS [$STEP_TAG]: $MESSAGE\e[0m"
            ;;
        "INFO")
            echo -e "   > $MESSAGE"
            ;;
    esac
}

# Wrapper pour les anciennes fonctions
msg_info() { log_msg "STEP" "TASK" "$1"; }
msg_success() { log_msg "SUCCESS" "TASK" "$1"; }
msg_error() {
    log_msg "ERROR" "FATAL" "$1";
    exit 1;
}
msg_warn() { log_msg "WARN" "WARNING" "$1"; }
# Gère les erreurs fatales (set -e)
trap 'log_msg "ERROR" "FATAL" "Script arrêté inopinément à la ligne $LINENO."' ERR

# --- Contenu du fichier my_app.conf ---
APACHE_CONFIG=$(cat <<EOF
<VirtualHost *:80>
    DocumentRoot $LIVE_SYMLINK/$PROJECT_SUBDIR/frontend_app/build
    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/frontend_app/build>
        Options +FollowSymLinks
        Require all granted
        AllowOverride All
        FallbackResource /index.html
    </Directory>
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
    WSGIDaemonProcess django_app python-home=$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/.venv
    WSGIProcessGroup django_app
    WSGIScriptAlias /api $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py process-group=django_app application-group=%{GLOBAL}
    <Directory $LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core>
        Options +FollowSymLinks
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>
    ErrorLog \${APACHE_LOG_DIR}/my_app-error.log
    CustomLog \${APACHE_LOG_DIR}/my_app-access.log combined
</VirtualHost>
EOF
)

# --- Vérification initiale ---
if [ "$EUID" -ne 0 ]; then
    msg_error "Ce script doit être lancé avec sudo. Ex: sudo ./deploy.sh"
fi

set -e
log_msg "STEP" "INIT" "Début du script d'installation."

# --- A. PRÉREQUIS SYSTÈME ---
msg_info "Mise à jour des paquets (la sortie va dans $LOG_FILE)..."
apt-get update >> "$LOG_FILE" 2>&1

msg_info "Installation des dépendances (Git, Apache, WSGI, Python, pipx)..."
apt-get install -y git apache2 libapache2-mod-wsgi-py3 python3-venv curl gpg pipx 2>&1 | tee -a "$LOG_FILE"
pipx ensurepath 2>&1 | tee -a "$LOG_FILE"
msg_success "Dépendances de base installées."

msg_info "Installation de Node.js et NPM (via NodeSource LTS)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >> "$LOG_FILE" 2>&1
apt-get install -y nodejs 2>&1 | tee -a "$LOG_FILE"
msg_success "Node.js et NPM installés."

# --- B. CLONAGE ET PERMISSIONS ---
msg_info "Préparation de SSH pour le clonage non-interactif..."
mkdir -p /root/.ssh
ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null
log_msg "INFO" "SSH" "known_hosts de root mis à jour."

msg_info "Nettoyage des anciennes installations..."
rm -rf "$BLUE_PATH" "$GREEN_PATH" "$LIVE_SYMLINK"
log_msg "INFO" "CLEANUP" "Anciens dossiers /var/www/ supprimés."

msg_info "Clonage du projet (via SSH) dans $BLUE_PATH..."
git clone "$GIT_URL" "$BLUE_PATH" 2>&1 | tee -a "$LOG_FILE"

msg_info "Création du groupe 'webmasters' et ajout des utilisateurs..."
groupadd webmasters || log_msg "INFO" "GROUP" "Le groupe 'webmasters' existe déjà."
usermod -aG webmasters "$PROJECT_USER"
usermod -aG webmasters www-data
log_msg "INFO" "GROUP" "Utilisateurs '$PROJECT_USER' et 'www-data' ajoutés à 'webmasters'."

msg_info "Application des permissions (chown, chmod, setgid)..."
chgrp webmasters /var/www
chmod 775 /var/www
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
echo "Installation de poetry via pipx (avec --force)..."
pipx install --force poetry
echo "Installation de poetry terminée."

pipx ensurepath

# --- C. INSTALLATION BACKEND (sur BLUE) ---
echo -e "\n--- [Sub-script] Installation du Backend Django sur BLUE... ---"
cd "$BLUE_PATH/$PROJECT_SUBDIR/backend_project"
\$HOME/.local/bin/poetry config virtualenvs.in-project true
\$HOME/.local/bin/poetry install --only main

echo -e "\n--- [Sub-script] Lancement de collectstatic et migrate... ---"
\$HOME/.local/bin/poetry run python src/manage.py collectstatic --noinput
\$HOME/.local/bin/poetry run python src/manage.py migrate

# --- D. INSTALLATION FRONTEND (sur BLUE) ---
echo -e "\n--- [Sub-script] Installation du Frontend React sur BLUE... ---"
cd "$BLUE_PATH/$PROJECT_SUBDIR/frontend_app"
npm install
npm run build

echo -e "\n--- [Sub-script] Installation sur BLUE terminée avec succès. ---"
EOF

chmod +x "$SUB_SCRIPT_PATH"
chown "$PROJECT_USER:$PROJECT_USER" "$SUB_SCRIPT_PATH"
log_msg "INFO" "SUB_SCRIPT" "Sous-script créé à $SUB_SCRIPT_PATH"

msg_info "Lancement du sous-script en tant que '$PROJECT_USER' (sortie capturée)..."
echo "****************************************************************"
echo ">>> VOUS DEVREZ ENTRER LE MOT DE PASSE POUR '$PROJECT_USER' <<<"
echo "****************************************************************"
# La sortie (stdout/stderr) du sous-script est logguée et affichée
su - "$PROJECT_USER" -c "$SUB_SCRIPT_PATH" 2>&1 | tee -a "$LOG_FILE"

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
log_msg "INFO" "APACHE" "Fichier my_app.conf créé."

msg_info "Activation du site 'my_app'..."
a2dissite 000-default.conf >> "$LOG_FILE" 2>&1 || log_msg "INFO" "APACHE" "000-default déjà désactivé."
a2ensite my_app.conf >> "$LOG_FILE" 2>&1 || log_msg "INFO" "APACHE" "my_app.conf déjà activé."

msg_info "Test de la configuration Apache..."
apache2ctl configtest 2>&1 | tee -a "$LOG_FILE"

msg_info "Redémarrage d'Apache..."
systemctl restart apache2
log_msg "INFO" "APACHE" "Service Apache redémarré."

# --- G. CONCLUSION ---
msg_success "Déploiement Blue/Green initial terminé !"
echo "Votre site devrait être accessible à http://<votre_ip>"
echo "LIVE pointe actuellement sur BLUE."
msg_info "En cas d'erreur 500, vérifiez les logs avec :"
echo "sudo tail -f /var/log/apache2/my_app-error.log"
echo "Le log de déploiement complet est dans : $LOG_FILE"

# Nettoyage
rm "$SUB_SCRIPT_PATH"
log_msg "STEP" "END" "Script d'installation terminé."