#!/bin/bash

# Script de "Terre Brûlée" pour désinstaller l'intégralité du projet.
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO

# --- Configuration ---
PROJECT_USER="vboxuser"
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
REPO_ROOT_LEGACY="/var/www/ADS_ReactDjango2"

# --- Configuration du Logging ---
LOG_FILE="/var/log/my_app_deployment.log"
SCRIPT_NAME="UNINSTALL"
# S'assure que le fichier log existe et est inscriptible
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

# --- Fonctions de Logging ---
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


# --- Vérification initiale ---
if [ "$EUID" -ne 0 ]; then
    msg_error "Ce script doit être lancé avec sudo. Ex: sudo ./uninstall_all.sh"
fi

set -e
log_msg "STEP" "INIT" "Début du script de désinstallation (Terre Brûlée)."

# --- 1. ARRÊT ET PURGE D'APACHE ---
msg_info "Arrêt et désinstallation d'Apache..."
systemctl stop apache2 || msg_warn "APACHE" "Apache n'était déjà pas démarré."
a2dissite my_app.conf || msg_warn "APACHE" "Site 'my_app' n'existait pas."
a2ensite 000-default.conf || msg_warn "APACHE" "Site '000-default' déjà activé."

log_msg "INFO" "APT" "Purge d'Apache et WSGI (la sortie va dans $LOG_FILE)..."
apt-get purge -y apache2 libapache2-mod-wsgi-py3 >> "$LOG_FILE" 2>&1
apt-get autoremove -y >> "$LOG_FILE" 2>&1
rm -f /etc/apache2/sites-available/my_app.conf
systemctl daemon-reload
msg_success "Apache purgé."

# --- 2. SUPPRESSION DES FICHIERS DU PROJET ---
msg_info "Suppression des dossiers du projet dans /var/www/..."
rm -rf "$BLUE_PATH"
rm -rf "$GREEN_PATH"
rm -f "$LIVE_SYMLINK"
rm -rf "$REPO_ROOT_LEGACY"
msg_success "Dossiers du projet supprimés."

# --- 3. SUPPRESSION DES DÉPENDANCES ---
msg_info "Désinstallation de Node.js, pipx, et autres outils..."
apt-get purge -y nodejs >> "$LOG_FILE" 2>&1 || msg_warn "APT" "Node.js n'était pas installé."
rm -f /etc/apt/sources.list.d/nodesource.list
apt-get purge -y pipx >> "$LOG_FILE" 2>&1 || msg_warn "APT" "pipx n'était pas installé."
rm -rf /root/.local/bin
rm -rf /root/.local/pipx
rm -rf /root/.local/share/pipx
apt-get purge -y python3-venv >> "$LOG_FILE" 2>&1 || msg_warn "APT" "python3-venv n'était pas installé."
apt-get autoremove -y >> "$LOG_FILE" 2>&1
msg_success "Dépendances purgées."

# --- 4. NETTOYAGE DES FICHIERS UTILISATEUR ($PROJECT_USER) ---
msg_info "Nettoyage des fichiers de configuration et caches de '$PROJECT_USER'..."
rm -f "/home/$PROJECT_USER/install_sub.sh"
rm -rf "/home/$PROJECT_USER/.local/bin"
rm -rf "/home/$PROJECT_USER/.local/pipx"
rm -rf "/home/$PROJECT_USER/.local/share/pipx" # Chemin correct
rm -rf "/home/$PROJECT_USER/.cache/pip"
rm -rf "/home/$PROJECT_USER/.cache/poetry"
rm -rf "/home/$PROJECT_USER/.npm"
msg_success "Fichiers de '$PROJECT_USER' nettoyés."

# --- 5. NETTOYAGE DES CLÉS SSH (Préservées) ---
log_msg "INFO" "SSH" "Nettoyage de known_hosts (clés privées préservées)..."
rm -f /root/.ssh/known_hosts
rm -f "/home/$PROJECT_USER/.ssh/known_hosts"
msg_success "'known_hosts' nettoyés."

# --- 6. NETTOYAGE DU GROUPE (Correction) ---
msg_info "Suppression du groupe 'webmasters'..."
# CORRECTION: Sépare les commandes et utilise msg_warn au lieu de || true
deluser "$PROJECT_USER" webmasters || msg_warn "DELUSER" "L'utilisateur '$PROJECT_USER' n'était pas dans 'webmasters'."
deluser www-data webmasters || msg_warn "DELUSER" "L'utilisateur 'www-data' n'était pas dans 'webmasters'."
delgroup webmasters || msg_warn "DELGROUP" "Le groupe 'webmasters' n'existait pas ou ne pouvait pas être supprimé."
msg_success "Nettoyage du groupe 'webmasters' terminé."

# --- F. CONCLUSION ---
msg_success "Désinstallation terminée !"
log_msg "STEP" "END" "Le système est prêt pour un nouveau test d'installation."