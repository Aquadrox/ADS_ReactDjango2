import json
from django.test import TestCase
from django.urls import reverse
from django.core.files.uploadedfile import SimpleUploadedFile


class UploadViewTests(TestCase):

    def setUp(self):
        # Récupère l'URL de notre vue.
        # 'upload_view' est le 'name' que nous avons défini dans api/urls.py
        self.url = reverse('upload_view')

    def test_upload_success(self):
        """
        Teste un upload réussi (scénario 201 CREATED).
        """
        # 1. Préparer les données (similaires à ce que fait React)
        json_data = json.dumps({"message": "test"})

        # Simule un faux fichier Excel
        file_data = b"Ceci est le contenu d'un faux fichier excel"
        test_file = SimpleUploadedFile("test_file.xlsx", file_data)

        # 2. Lancer la requête POST
        response = self.client.post(self.url, data={
            'jsonData': json_data,
            'excelFile': test_file
        })

        # 3. Vérifier le résultat
        self.assertEqual(response.status_code, 201)
        response_json = response.json()
        self.assertEqual(response_json['status'], 'Succès')
        self.assertEqual(response_json['json_recu']['message'], 'test')
        self.assertEqual(response_json['nom_fichier'], 'test_file.xlsx')

    def test_upload_missing_json(self):
        """
        Teste une requête échouée car 'jsonData' est manquant (scénario 400).
        """
        # 1. Préparer les données (seulement le fichier)
        file_data = b"file_content"
        test_file = SimpleUploadedFile("test_file.xlsx", file_data)

        # 2. Lancer la requête POST
        response = self.client.post(self.url, data={
            'excelFile': test_file
        })

        # 3. Vérifier le résultat
        self.assertEqual(response.status_code, 400)
        self.assertIn('error', response.json())

    def test_upload_missing_file(self):
        """
        Teste une requête échouée car 'excelFile' est manquant (scénario 400).
        """
        # 1. Préparer les données (seulement le JSON)
        json_data = json.dumps({"message": "test"})

        # 2. Lancer la requête POST
        response = self.client.post(self.url, data={
            'jsonData': json_data
        })

        # 3. Vérifier le résultat
        self.assertEqual(response.status_code, 400)
        self.assertIn('error', response.json())
