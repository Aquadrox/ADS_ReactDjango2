from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.parsers import MultiPartParser
from rest_framework import status
import json
import os
from django.conf import settings


class UploadView(APIView):
    # Dire à DRF d'utiliser le parser pour les formulaires "multipart"
    # (qui gère les fichiers)
    parser_classes = (MultiPartParser,)

    def post(self, request, *args, **kwargs):
        try:
            # 1. Récupérer les données JSON (envoyées comme texte)
            json_data_str = request.data.get('jsonData')
            if not json_data_str:
                return Response(
                    {"error": "Le champ 'jsonData' est manquant."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Convertir le texte JSON en objet Python
            json_data = json.loads(json_data_str)

            # 2. Récupérer le fichier
            excel_file = request.data.get('excelFile')
            if not excel_file:
                return Response(
                    {"error": "Le champ 'excelFile' est manquant."},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # 3. Sauvegarder le fichier (simplement)
            # Crée le dossier 'media' s'il n'existe pas
            os.makedirs(settings.MEDIA_ROOT, exist_ok=True)

            file_path = os.path.join(settings.MEDIA_ROOT, excel_file.name)

            # Écrire le fichier sur le disque
            with open(file_path, 'wb+') as destination:
                for chunk in excel_file.chunks():
                    destination.write(chunk)

            # 4. Envoyer la réponse de succès
            return Response({
                "status": "Succès",
                "message": "Fichiers reçus avec succès !",
                "json_recu": json_data,
                "nom_fichier": excel_file.name,
                "chemin_sauvegarde": file_path
            }, status=status.HTTP_201_CREATED)

        except json.JSONDecodeError:
            return Response(
                {"error": "JSON mal formaté."},
                status=status.HTTP_400_BAD_REQUEST
            )
        except Exception as e:
            return Response(
                {"error": f"Une erreur serveur est survenue: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )
