#!/bin/bash
set -e # Arrête le script si une commande échoue

# --- Configuration ---
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
GIT_BRANCH="master"
PROJECT_SUBDIR="my_app" # Le sous-dossier de votre projet dans Git

echo "--- Démarrage du déploiement Blue/Green ---"

# --- 1. DÉTERMINER LES RÔLES (Le Garde-Fou) ---
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

echo "Environnement LIVE actuel : $LIVE_ENV_NAME ($CURRENT_LIVE_PATH)"
echo "Environnement IDLE (cible) : $IDLE_ENV_NAME ($IDLE_ENV_PATH)"


# --- 2. DÉPLOYER SUR L'ENVIRONNEMENT INACTIF ---
echo "--- Déploiement sur $IDLE_ENV_NAME ---"
cd "$IDLE_ENV_PATH"

echo "[1/5] Récupération des mises à jour de GitHub (fetch & reset)..."
git fetch origin
git reset --hard "origin/$GIT_BRANCH"

echo "[2/5] Installation des dépendances Backend (Poetry)..."
cd "$IDLE_ENV_PATH/$PROJECT_SUBDIR/backend_project"
poetry install --only main

echo "[3/5] Exécution des migrations Django..."
poetry run python src/manage.py migrate

echo "[4.A/5] Installation Frontend (npm)..."
cd "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app"
npm install

# --- NOUVELLE ÉTAPE : CORRECTION DES PERMISSIONS ---
echo "[4.B/5] Rétablissement des permissions d'exécution..."
if [ -d "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app/node_modules/.bin" ]; then
    chmod +x "$IDLE_ENV_PATH/$PROJECT_SUBDIR/frontend_app/node_modules/.bin/"*
    echo "Permissions pour node_modules/.bin corrigées."
else
    echo "AVERTISSEMENT: Dossier node_modules/.bin introuvable."
fi
# --------------------------------------------------

echo "[4.C/5] Build Frontend (npm run build)..."
# Cette commande va maintenant fonctionner
npm run build

echo "--- Déploiement sur $IDLE_ENV_NAME terminé. ---"

# --- 3. (OPTIONNEL) TESTS DE SANTÉ (Health Check) ---
echo "Health Check réussi (simulé)."


# --- 4. LA BASCULE (ATOMIQUE) ---
echo "--- Bascule du trafic : $LIVE_ENV_NAME -> $IDLE_ENV_NAME ---"
ln -sfn "$IDLE_ENV_PATH" "$LIVE_SYMLINK"


# --- 5. RECHARGEMENT DU BACKEND (WSGI) ---
echo "Rechargement du serveur WSGI..."
touch "$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py"

echo "--- Déploiement Blue/Green terminé avec succès. ---"
echo "Le nouvel environnement LIVE est : $IDLE_ENV_NAME"

