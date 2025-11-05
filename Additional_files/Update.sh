#!/bin/bash
set -e # Arrête le script si une commande échoue

# --- Configuration ---
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
GIT_BRANCH="master"
PROJECT_SUBDIR="my_app"

# --- Configuration du Logging ---
LOG_FILE="/var/log/my_app_deployment.log"
SCRIPT_NAME="UPDATE"

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
log_msg "STEP" "INIT" "Démarrage du déploiement Blue/Green (Mise à jour)."

# --- 1. DÉTERMINER LES RÔLES ---
CURRENT_LIVE_PATH=$(readlink -f "$LIVE_SYMLINK")
IDLE_ENV_PATH=""
LIVE_ENV_NAME=""
IDLE_ENV_NAME=""

if [ "$CURRENT_LIVE_PATH" == "$BLUE_PATH" ]; then
    LIVE_ENV_NAME="BLUE"
    IDLE_ENV_NAME="GREEN"
    IDLE_ENV_PATH="$GREEN_PATH"
else
    LIVE_ENV_NAME="GREEN"
    IDLE_ENV_NAME="BLUE"
    IDLE_ENV_PATH="$BLUE_PATH"
fi

log_msg "INFO" "ENV" "Environnement LIVE actuel : $LIVE_ENV_NAME ($CURRENT_LIVE_PATH)"
log_msg "INFO" "ENV" "Environnement IDLE (cible) : $IDLE_ENV_NAME ($IDLE_ENV_PATH)"


# --- 2. DÉPLOYER SUR L'ENVIRONNEMENT INACTIF ---
log_msg "STEP" "DEPLOY_IDLE" "Déploiement sur $IDLE_ENV_NAME..."
cd "$IDLE_ENV_PATH"

log_msg "INFO" "GIT" "[1/5] Récupération des mises à jour de GitHub (fetch & reset)..."
git fetch origin 2>&1 | tee -a "$LOG_FILE"
git reset --hard "origin/$GIT_BRANCH" 2>&1 | tee -a "$LOG_FILE"

log_msg "INFO" "BACKEND" "[2/5] Installation des dépendances Backend (Poetry)..."
cd "$IDLE_ENV_PATH/$PROJECT_SUBDIR/backend_project"
poetry install --only main 2>&1 | tee -a "$LOG_FILE"

log_msg "INFO" "BACKEND" "[3/5] Exécution des migrations Django..."
poetry run python src/manage.py migrate 2>&1 | tee -a "$LOG_FILE"

log_msg "INFO" "FRONTEND" "[4.A/5] Installation Frontend (npm)..."
cd "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app"
npm install 2>&1 | tee -a "$LOG_FILE"

log_msg "INFO" "FRONTEND" "[4.B/5] Rétablissement des permissions d'exécution..."
if [ -d "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app/node_modules/.bin" ]; then
    chmod +x "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app/node_modules/.bin/"*
    log_msg "SUCCESS" "PERMISSIONS" "Permissions pour node_modules/.bin corrigées."
else
    log_msg "WARN" "PERMISSIONS" "Dossier node_modules/.bin introuvable."
fi

log_msg "INFO" "FRONTEND" "[4.C/5] Build Frontend (npm run build)..."
npm run build 2>&1 | tee -a "$LOG_FILE"

log_msg "SUCCESS" "DEPLOY_IDLE" "Déploiement sur $IDLE_ENV_NAME terminé."

# --- 3. (OPTIONNEL) TESTS DE SANTÉ (Health Check) ---
log_msg "INFO" "HEALTH_CHECK" "Health Check réussi (simulé)."


# --- 4. LA BASCULE (ATOMIQUE) ---
log_msg "STEP" "SWAP" "Bascule du trafic : $LIVE_ENV_NAME -> $IDLE_ENV_NAME"
ln -sfn "$IDLE_ENV_PATH" "$LIVE_SYMLINK"
log_msg "SUCCESS" "SWAP" "Lien symbolique LIVE mis à jour."


# --- 5. RECHARGEMENT DU BACKEND (WSGI) ---
log_msg "STEP" "RELOAD" "Rechargement du serveur WSGI..."
touch "$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py"
log_msg "SUCCESS" "RELOAD" "Fichier WSGI 'touché' pour rechargement."

log_msg "STEP" "END" "Déploiement Blue/Green terminé avec succès. Le nouvel environnement LIVE est : $IDLE_ENV_NAME"