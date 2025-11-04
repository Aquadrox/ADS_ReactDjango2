import React, { useState } from 'react';
import axios from 'axios';

function App() {
  const [file, setFile] = useState(null);
  const [jsonData, setJsonData] = useState('{"message": "Bonjour Django"}');
  const [responseMsg, setResponseMsg] = useState('');

  // Gère le changement de l'input fichier
  const handleFileChange = (e) => {
    setFile(e.target.files[0]);
  };

  // Gère le changement du textarea JSON
  const handleJsonChange = (e) => {
    setJsonData(e.target.value);
  };

  // Gère l'envoi du formulaire
  const handleSubmit = async (e) => {
    e.preventDefault(); // Empêche le rechargement de la page
    setResponseMsg('Envoi en cours...');

    if (!file) {
      setResponseMsg('Erreur : Veuillez sélectionner un fichier.');
      return;
    }

    // Nous devons utiliser FormData pour envoyer des fichiers
    const formData = new FormData();

    // 'excelFile' et 'jsonData' DOIVENT correspondre aux clés attendues par Django
    formData.append('excelFile', file);
    formData.append('jsonData', jsonData);

    try {
      // L'URL '/api/upload/' sera gérée par le proxy (en dev)
      // et par Apache (en prod)
      const response = await axios.post('/api/upload/', formData, {
        headers: {
          // Le 'Content-Type' est géré automatiquement par axios
          // quand on utilise FormData
        },
      });

      console.log('Réponse du serveur:', response.data);
      setResponseMsg(`Succès ! Réponse : ${JSON.stringify(response.data)}`);

    } catch (error) {
      console.error('Erreur lors de l\'envoi:', error);
      let errorText = error.message;
      if (error.response && error.response.data) {
        errorText = JSON.stringify(error.response.data);
      }
      setResponseMsg(`Erreur : ${errorText}`);
    }
  };

  return (
    <div style={{ padding: '20px' }}>
      <h1>Test d'Upload Django + React</h1>
      <form onSubmit={handleSubmit}>
        <div>
          <h3>1. Données JSON à envoyer</h3>
          <textarea
            value={jsonData}
            onChange={handleJsonChange}
            rows="5"
            cols="50"
          />
        </div>
        <hr />
        <div>
          <h3>2. Fichier (Excel ou autre)</h3>
          <input
            type="file"
            onChange={handleFileChange}
            accept=".xls,.xlsx,.csv,.txt,.pdf" // Accepte plusieurs types
          />
        </div>
        <hr />
        <button type="submit">Envoyer au Backend</button>
      </form>

      {responseMsg && (
        <div style={{ marginTop: '20px', background: '#f0f0f0', padding: '10px' }}>
          <h3>Réponse du Serveur :</h3>
          <pre>{responseMsg}</pre>
        </div>
      )}
    </div>
  );
}

export default App;