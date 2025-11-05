#!/bin/bash

# Script de "Terre Brûlée" pour désinstaller l'intégralité du projet et de ses dépendances.
#
# DOIT ÊTRE EXÉCUTÉ AVEC SUDO
# sudo ./uninstall_all.sh
#

# --- Configuration ---
# (Assurez-vous que cela correspond à vos scripts)
PROJECT_USER="vboxuser"
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
REPO_ROOT_LEGACY="/var/www/ADS_ReactDjango2" # Au cas où l'ancien dossier existe

# --- Fonctions d'aide ---
msg_info() {
    echo -e "\n\e[34m--- $1 ---\e[0m"
}
msg_success() {
    echo -e "\e[32m✅ $1\e[0m"
}
msg_warning() {
    echo -e "\e[33m⚠️ $1\e[0m"
}

# --- Vérification initiale ---
if [ "$EUID" -ne 0 ]; then
    echo -e "\e[31m❌ ERREUR: Ce script doit être lancé avec sudo. Ex: sudo ./uninstall_all.sh\e[0m" >&2
    exit 1
fi

set -e # Arrête le script si une commande échoue (sauf si '|| true' est utilisé)

# --- 1. ARRÊT ET PURGE D'APACHE ---
msg_info "Arrêt et désinstallation d'Apache..."
systemctl stop apache2 || true
a2dissite my_app.conf || true
a2ensite 000-default.conf || true

# Purge supprime les paquets ET leurs fichiers de configuration système
apt-get purge -y apache2 libapache2-mod-wsgi-py3
apt-get autoremove -y # Nettoie les dépendances orphelines
rm -f /etc/apache2/sites-available/my_app.conf
systemctl daemon-reload
msg_success "Apache purgé."

# --- 2. SUPPRESSION DES FICHIERS DU PROJET ---
msg_info "Suppression des dossiers du projet dans /var/www/..."
rm -rf "$BLUE_PATH"
rm -rf "$GREEN_PATH"
rm -f "$LIVE_SYMLINK"
rm -rf "$REPO_ROOT_LEGACY" # Nettoyage de l'ancien dossier de clonage
msg_success "Dossiers du projet supprimés."

# --- 3. SUPPRESSION DES DÉPENDANCES ---
msg_info "Désinstallation de Node.js, pipx, et autres outils..."
# Suppression de Node.js (installé via NodeSource)
apt-get purge -y nodejs
rm -f /etc/apt/sources.list.d/nodesource.list

# Suppression de pipx et des paquets installés par root (Poetry)
apt-get purge -y pipx
rm -rf /root/.local/bin
rm -rf /root/.local/pipx
rm -rf /root/.local/share/pipx # Ajout du nouveau chemin

# Suppression des autres dépendances
apt-get purge -y python3-venv

apt-get autoremove -y
msg_success "Dépendances purgées."

# --- 4. NETTOYAGE DES FICHIERS UTILISATEUR ($PROJECT_USER) ---
msg_info "Nettoyage des fichiers de configuration et caches de '$PROJECT_USER'..."
# Le script est lancé par root, donc nous ciblons /home/$PROJECT_USER
rm -f "/home/$PROJECT_USER/install_sub.sh"
rm -rf "/home/$PROJECT_USER/.local/bin"      # Binaires pipx (Poetry)
rm -rf "/home/$PROJECT_USER/.local/pipx"     # Environnements pipx (Ancien chemin)
# --- CORRECTION ---
rm -rf "/home/$PROJECT_USER/.local/share/pipx" # Environnements pipx (Nouveau chemin)
# --- FIN CORRECTION ---
rm -rf "/home/$PROJECT_USER/.cache/pip"
rm -rf "/home/$PROJECT_USER/.cache/poetry"
rm -rf "/home/$PROJECT_USER/.npm"            # Cache NPM
msg_success "Fichiers de '$PROJECT_USER' nettoyés."

# --- 5. NETTOYAGE DES CLÉS SSH (Modification) ---
#msg_info "Nettoyage du fichier 'known_hosts' (les clés sont préservées)..."
## Au lieu de 'rm -rf /root/.ssh', nous supprimons uniquement le
## fichier 'known_hosts' que le script d'installation recrée.
## Nous préservons les clés (id_ed25519) pour ne pas avoir à
## les ré-autoriser sur GitHub.
#rm -f /root/.ssh/known_hosts
#rm -f "/home/$PROJECT_USER/.ssh/known_hosts"
#msg_success "Fichiers 'known_hosts' nettoyés."

# --- 6. NETTOYAGE DU GROUPE ---
msg_info "Suppression du groupe 'webmasters'..."
# Utilise '|| true' au cas où l'utilisateur/groupe n'existerait pas
deluser "$PROJECT_USER" webmasters || true
deluser www-data webmasters || true
delgroup webmasters || true
msg_success "Groupe 'webmasters' supprimé."

# --- F. CONCLUSION ---
msg_success "Désinstallation terminée !"
echo "Le système est prêt pour un nouveau test d'installation."