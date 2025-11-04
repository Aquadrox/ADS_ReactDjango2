#!/bin/bash

# Script de déploiement automatisé pour Django + React + Apache
#
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO
# sudo ./deploy.sh
#
# PRÉREQUIS:
# 1. Le dossier du projet 'my_app' doit se trouver dans '/home/{PROJECT_USER}/my_app'
# 2. Le script s'occupe d'installer Apache, mod_wsgi, Python vEnv,
#    Poetry, Node.js et NPM.

# --- Configuration ---
# L'utilisateur NON-root qui possède les fichiers et exécute les builds.
# !! IMPORTANT !! Remplacez 'vboxuser' si votre nom d'utilisateur est différent.
PROJECT_USER="vboxuser"

# Le dossier où le projet sera copié
PROJECT_PATH="/var/www/my_app"

# Le dossier source du projet
SOURCE_PATH="/home/$PROJECT_USER/my_app"


# --- Contenu du fichier my_app.conf ---
# (Le contenu du fichier de conf Apache)

APACHE_CONFIG=$(cat <<EOF
#/etc/apache2/sites-available/my_app.conf
<VirtualHost *:80>
    # Optionnel: Nom de domaine
    # ServerName votre_domaine.com

    # --- 1. Servir le Frontend React (le 'build') ---
    # DocumentRoot pointe vers le build de React
    DocumentRoot $PROJECT_PATH/frontend_app/build

    <Directory $PROJECT_PATH/frontend_app/build>
        Require all granted
        AllowOverride All
        # Permet à React (React Router) de gérer les routes
        FallbackResource /index.html
    </Directory>

    # --- 2. Servir les fichiers 'media' (uploads Excel) ---
    Alias /media/ $PROJECT_PATH/backend_project/src/media/
    <Directory $PROJECT_PATH/backend_project/src/media>
        Require all granted
    </Directory>

    # --- 3. Servir les fichiers 'static' (admin Django, etc.) ---
    Alias /django-static/ $PROJECT_PATH/backend_project/src/staticfiles/

    <Directory $PROJECT_PATH/backend_project/src/staticfiles>
        Require all granted
    </Directory>

    # --- 4. Connecter l'API Django avec mod_wsgi ---
    WSGIDaemonProcess django_app python-home=$PROJECT_PATH/backend_project/.venv
    WSGIProcessGroup django_app
    WSGIScriptAlias /api $PROJECT_PATH/backend_project/src/core/wsgi.py process-group=django_app application-group=%{GLOBAL}

    <Directory $PROJECT_PATH/backend_project/src/core>
        <Files wsgi.py>
            Require all granted
        </Files>
    </Directory>

    # Gestion des erreurs
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

if [ ! -d "$SOURCE_PATH" ]; then
    msg_error "Le dossier source '$SOURCE_PATH' est introuvable."
fi

# Arrête le script si une commande échoue
set -e

# --- A. PRÉREQUIS SYSTÈME ---
msg_info "Mise à jour des paquets et installation des dépendances..."
apt-get update > /dev/null
# Ajout de curl, gpg (pour NodeSource) et pipx (pour Poetry)
apt-get install -y apache2 libapache2-mod-wsgi-py3 python3-venv curl gpg pipx > /dev/null
msg_success "Dépendances de base installées."

msg_info "Installation de Node.js et NPM (via NodeSource LTS)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash - > /dev/null
apt-get install -y nodejs > /dev/null
msg_success "Node.js et NPM installés."

msg_info "Installation de Poetry (via pipx)..."
pipx install poetry > /dev/null
msg_success "Poetry installé."

# --- B. COPIE ET PERMISSIONS ---
msg_info "Copie des fichiers du projet vers $PROJECT_PATH..."
# Évite une erreur si le dossier existe déjà
mkdir -p "$PROJECT_PATH"
cp -r "$SOURCE_PATH"/* "$PROJECT_PATH"

msg_info "Création du groupe 'webmasters' et ajout des utilisateurs..."
# '|| true' pour ne pas échouer si le groupe existe déjà
groupadd webmasters || true
usermod -aG webmasters "$PROJECT_USER"
usermod -aG webmasters www-data

msg_info "Application des permissions (chown, chmod, setgid)..."
chown -R "$PROJECT_USER:webmasters" "$PROJECT_PATH"
find "$PROJECT_PATH" -type d -exec chmod 775 {} \;
find "$PROJECT_PATH" -type f -exec chmod 664 {} \;
find "$PROJECT_PATH" -type d -exec chmod g+s {} \;
msg_success "Permissions configurées."

# --- C & D. INSTALLATION BACKEND & FRONTEND (via sous-script) ---

# Nous créons un sous-script qui sera exécuté par 'su'
# C'est ce qui résout le problème de re-login pour 'vboxuser'
msg_info "Création du sous-script d'installation..."
SUB_SCRIPT_PATH="/tmp/install_sub.sh"

cat << EOF > "$SUB_SCRIPT_PATH"
#!/bin/bash
set -e # Arrête le sous-script en cas d'erreur

echo "--- [Sub-script] Démarrage en tant que \$(whoami) (avec les groupes: \$(id -Gn)) ---"

# S'assure que pipx/poetry est dans le PATH de cet environnement
echo "--- [Sub-script] Configuration du PATH pour Poetry..."
export PATH="\$HOME/.local/bin:\$PATH"
pipx ensurepath # S'assure que le .bashrc est à jour pour les futures sessions

# --- C. INSTALLATION BACKEND ---
echo "--- [Sub-script] Installation du Backend Django..."
cd "$PROJECT_PATH/backend_project"
poetry config virtualenvs.in-project true
poetry install --only main

# Utilise 'poetry run' au lieu de 'poetry shell'
echo "--- [Sub-script] Lancement de collectstatic et migrate..."
poetry run python src/manage.py collectstatic --noinput
poetry run python src/manage.py migrate

# --- D. INSTALLATION FRONTEND ---
echo "--- [Sub-script] Installation du Frontend React..."
cd "$PROJECT_PATH/frontend_app"
npm install
npm run build

echo "--- [Sub-script] Installation terminée avec succès. ---"
EOF

# Assure que l'utilisateur peut exécuter le sous-script
chmod +x "$SUB_SCRIPT_PATH"
chown "$PROJECT_USER:$PROJECT_USER" "$SUB_SCRIPT_PATH"

# Lancement du sous-script en tant que $PROJECT_USER
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
# '|| true' pour ignorer les erreurs si déjà activé/désactivé
a2dissite 000-default.conf || true
a2ensite my_app.conf || true

msg_info "Test de la configuration Apache..."
apache2ctl configtest
# La commande 'set -e' arrêtera le script ici si le test échoue

msg_info "Redémarrage d'Apache..."
systemctl restart apache2

# --- F. CONCLUSION ---
msg_success "Déploiement terminé !"
echo "Votre site devrait être accessible à http://<votre_ip>"
msg_info "En cas d'erreur 500, vérifiez les logs avec :"
echo "sudo tail -f /var/log/apache2/my_app-error.log"

# Nettoyage
rm "$SUB_SCRIPT_PATH"

