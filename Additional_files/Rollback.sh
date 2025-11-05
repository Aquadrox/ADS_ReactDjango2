#!/bin/bash
set -e # Arrête le script si une commande échoue

# --- Configuration ---
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
PROJECT_SUBDIR="my_app"

# --- Configuration du Logging ---
LOG_FILE="/var/log/my_app_deployment.log"
SCRIPT_NAME="ROLLBACK"

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
trap 'log_msg "ERROR" "FATAL" "Script arrêté inopinément à la ligne $LINENO."' ERR

# --- Démarrage ---
log_msg "STEP" "INIT" "Démarrage du ROLLBACK (Retour Arrière)."

# --- AVERTISSEMENT IMPORTANT ---
log_msg "WARN" "DB_MIGRATE" "Ce script ne gère PAS les migrations de base de données."
log_msg "INFO" "DB_MIGRATE" "Si le déploiement qui a échoué contenait une migration ('manage.py migrate'),"
log_msg "INFO" "DB_MIGRATE" "un rollback du code peut casser l'application si l'ancien code n'est pas"
log_msg "INFO" "DB_MIGRATE" "compatible avec le nouveau schéma de la base de données."
echo "--------------------------------------------------------"


# --- 1. DÉTERMINER LES RÔLES ---
CURRENT_LIVE_PATH=$(readlink -f "$LIVE_SYMLINK")
ROLLBACK_TARGET_PATH=""
LIVE_ENV_NAME=""
ROLLBACK_ENV_NAME=""

if [ "$CURRENT_LIVE_PATH" == "$BLUE_PATH" ]; then
    LIVE_ENV_NAME="BLUE"
    ROLLBACK_ENV_NAME="GREEN"
    ROLLBACK_TARGET_PATH="$GREEN_PATH"
else
    LIVE_ENV_NAME="GREEN"
    ROLLBACK_ENV_NAME="BLUE"
    ROLLBACK_TARGET_PATH="$BLUE_PATH"
fi

log_msg "INFO" "ENV" "Environnement LIVE (en échec) : $LIVE_ENV_NAME ($CURRENT_LIVE_PATH)"
log_msg "INFO" "ENV" "Cible du Rollback (stable)   : $ROLLBACK_ENV_NAME ($ROLLBACK_TARGET_PATH)"


# --- 2. LA BASCULE (ATOMIQUE) ---
log_msg "STEP" "SWAP" "Bascule du trafic : $LIVE_ENV_NAME -> $ROLLBACK_ENV_NAME"
ln -sfn "$ROLLBACK_TARGET_PATH" "$LIVE_SYMLINK"
log_msg "SUCCESS" "SWAP" "Lien symbolique LIVE mis à jour."


# --- 3. RECHARGEMENT DU BACKEND (WSGI) ---
log_msg "STEP" "RELOAD" "Rechargement du serveur WSGI..."
touch "$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py"
log_msg "SUCCESS" "RELOAD" "Fichier WSGI 'touché' pour rechargement."

log_msg "STEP" "END" "Rollback terminé avec succès. L'environnement LIVE est maintenant : $ROLLBACK_ENV_NAME"