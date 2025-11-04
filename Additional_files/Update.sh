#!/bin/bash

# ===================================================================
# SCRIP DE MISE À JOUR (POST-INSTALLATION)
#
# DOIT ÊTRE EXÉCUTÉ PAR L'UTILISATEUR PROPRIÉTAIRE (ex: 'vboxuser')
# NE PAS UTILISER 'sudo'
#
# Usage:
# 1. Placez ce script (ex: /home/vboxuser/update.sh)
# 2. Donnez-lui les droits d'exécution: chmod +x /home/vboxuser/update.sh
# 3. Lancez-le: /home/vboxuser/update.sh
# ===================================================================

# Arrête le script si une commande échoue
set -e

# --- Configuration ---
# (Ces chemins doivent correspondre à votre script d'installation)
REPO_ROOT="/var/www/ADS_ReactDjango2"
BACKEND_DIR="$REPO_ROOT/my_app/backend_project"
FRONTEND_DIR="$REPO_ROOT/my_app/frontend_app"

# --- Fonctions d'aide ---
msg_info() {
    echo -e "\n\e[34m--- $1 ---\e[0m"
}
msg_success() {
    echo -e "\e[32m✅ $1\e[0m"
}

# --- 0. Préparation de l'environnement ---
# IMPORTANT: S'assure que 'poetry' est dans le PATH
export PATH="$HOME/.local/bin:$PATH"

msg_info "Démarrage de la mise à jour..."

# --- 1. Récupération du code ---
msg_info "1/5: Récupération des mises à jour de GitHub (git pull)..."
cd "$REPO_ROOT"
# 'git pull' mettra à jour la branche actuellement active
git pull

# --- 2. Mise à jour du Backend ---
msg_info "2/5: Mise à jour des dépendances Backend (poetry install)..."
cd "$BACKEND_DIR"
# 'poetry install' n'installe que ce qui a changé
poetry install --only main

msg_info "3/5: Application des migrations de la BDD (migrate)..."
poetry run python src/manage.py migrate

msg_info "4/5: Collecte des fichiers statiques (collectstatic)..."
# --noinput est crucial pour les scripts automatisés
poetry run python src/manage.py collectstatic --noinput

# --- 3. Mise à jour du Frontend ---
msg_info "5/5: Reconstruction du Frontend (npm install & build)..."
cd "$FRONTEND_DIR"
# 'npm install' n'installe que ce qui a changé dans package.json
npm install
npm run build

# --- 4. Redémarrage de l'application ---
msg_info "Redémarrage de l'application Django (touch wsgi.py)..."
# C'est la méthode rapide pour que mod_wsgi recharge le code Python
touch "$BACKEND_DIR/src/core/wsgi.py"

msg_success "Mise à jour terminée avec succès !"

