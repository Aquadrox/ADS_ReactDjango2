#!/bin/bash

# ===================================================================
# SCRIP DE MISE À JOUR v3 (Robuste)
#
# Utilise 'git reset --hard' pour forcer la synchronisation et
# éviter les erreurs de "branches divergentes".
#
# DOIT ÊTRE EXÉCUTÉ PAR L'UTILISATEUR PROPRIÉTAIRE (ex: 'vboxuser')
# ===================================================================

# Arrête le script si une commande échoue
set -e

# --- Configuration ---
REPO_ROOT="/var/www/ADS_ReactDjango2"
BACKEND_DIR="$REPO_ROOT/my_app/backend_project"
FRONTEND_DIR="$REPO_ROOT/my_app/frontend_app"
# La branche que vous voulez déployer
GIT_BRANCH="master"

# --- Fonctions d'aide ---
msg_info() {
    echo -e "\n\e[34m--- $1 ---\e[0m"
}
msg_success() {
    echo -e "\e[32m✅ $1\e[0m"
}

# --- 0. Préparation de l'environnement ---
export PATH="$HOME/.local/bin:$PATH"

msg_info "Démarrage de la mise à jour..."

# --- 0.5. Préparation SSH ---
msg_info "0.5/5: Vérification de l'hôte SSH GitHub..."
mkdir -p "$HOME/.ssh"
ssh-keyscan github.com >> "$HOME/.ssh/known_hosts"

# --- 1. Récupération du code (Méthode robuste) ---
msg_info "1/5: Récupération des mises à jour de GitHub (fetch & reset)..."
cd "$REPO_ROOT"
# Étape 1: Télécharge les dernières infos de GitHub
git fetch origin
# Étape 2: Force la branche locale à correspondre à celle de GitHub
# Cela supprime toutes les modifications locales !
git reset --hard "origin/$GIT_BRANCH"

msg_success "Le code est maintenant synchronisé avec $GIT_BRANCH."

# --- 2. Mise à jour du Backend ---
msg_info "2/5: Mise à jour des dépendances Backend (poetry install)..."
cd "$BACKEND_DIR"
poetry install --only main

msg_info "3/5: Application des migrations de la BDD (migrate)..."
poetry run python src/manage.py migrate

msg_info "4/5: Collecte des fichiers statiques (collectstatic)..."
poetry run python src/manage.py collectstatic --noinput

# --- 3. Mise à jour du Frontend ---
msg_info "5/5: Reconstruction du Frontend (npm install & build)..."
cd "$FRONTEND_DIR"
npm install
npm run build

# --- 4. Redémarrage de l'application ---
msg_info "Redémarrage de l'application Django (touch wsgi.py)..."
touch "$BACKEND_DIR/src/core/wsgi.py"

msg_success "Mise à jour terminée avec succès !"

