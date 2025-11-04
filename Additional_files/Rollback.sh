#!/bin/bash
set -e # Arrête le script si une commande échoue

# --- Configuration ---
# (Doit être identique à votre script de déploiement)
BLUE_PATH="/var/www/my_app_blue"
GREEN_PATH="/var/www/my_app_green"
LIVE_SYMLINK="/var/www/my_app_live"
PROJECT_SUBDIR="my_app"

echo "--- Démarrage du ROLLBACK (Retour Arrière) ---"

# --- AVERTISSEMENT IMPORTANT ---
echo -e "\n\e[31mATTENTION : Ce script ne gère PAS les migrations de base de données.\e[0m"
echo "Si le déploiement qui a échoué contenait une migration ('manage.py migrate'),"
echo "un rollback du code peut casser l'application si l'ancien code n'est pas"
echo "compatible avec le nouveau schéma de la base de données."
echo "Pour une démo, c'est sans danger."
echo -e "--------------------------------------------------------\n"


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

echo "Environnement LIVE (en échec) : $LIVE_ENV_NAME ($CURRENT_LIVE_PATH)"
echo "Cible du Rollback (stable)   : $ROLLBACK_ENV_NAME ($ROLLBACK_TARGET_PATH)"


# --- 2. LA BASCULE (ATOMIQUE) ---
echo "--- Bascule du trafic : $LIVE_ENV_NAME -> $ROLLBACK_ENV_NAME ---"
ln -sfn "$ROLLBACK_TARGET_PATH" "$LIVE_SYMLINK"


# --- 3. RECHARGEMENT DU BACKEND (WSGI) ---
echo "Rechargement du serveur WSGI..."
touch "$LIVE_SYMLINK/$PROJECT_SUBDIR/backend_project/src/core/wsgi.py"

echo -e "\n\e[32m✅ Rollback terminé avec succès.\e[0m"
echo "L'environnement LIVE est maintenant : $ROLLBACK_ENV_NAME"
