import React, { useState } from 'react';
import axios from 'axios';

// --- Icon components (simple SVGs) ---
// Icône de chargement (spinner)
const SpinnerIcon = () => (
  <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
  </svg>
);

// Icône pour le fichier
const FileIcon = () => (
  <svg className="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M7 16a4 4 0 01-4-4V6a2 2 0 012-2h10a2 2 0 012 2v6a4 4 0 01-4 4H7z"></path>
    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 11V3m0 8l-2.5-2.5M12 11l2.5-2.5"></path>
  </svg>
);

// --- Alert component for success/error ---
const Alert = ({ message, type }) => {
  const isError = type === 'error';
  const bgColor = isError ? 'bg-red-100' : 'bg-green-100';
  const borderColor = isError ? 'border-red-400' : 'border-green-400';
  const textColor = isError ? 'text-red-700' : 'text-green-700';
  const title = isError ? 'Erreur' : 'Succès';

  return (
    <div className={`border ${borderColor} ${bgColor} ${textColor} px-4 py-3 rounded-lg relative`} role="alert">
      <strong className="font-bold">{title} !</strong>
      <pre className="block sm:inline text-sm whitespace-pre-wrap">{message}</pre>
    </div>
  );
};

function App() {
  const [file, setFile] = useState(null);
  const [fileName, setFileName] = useState('Aucun fichier choisi');
  const [jsonData, setJsonData] = useState('{\n  "message": "Bonjour Django",\n  "projet": "Démo CI/CD"\n}');
  const [responseMsg, setResponseMsg] = useState(null); // { message: '', type: 'success' | 'error' }
  const [isLoading, setIsLoading] = useState(false);

  const handleFileChange = (e) => {
    if (e.target.files && e.target.files[0]) {
      setFile(e.target.files[0]);
      setFileName(e.target.files[0].name);
    } else {
      setFile(null);
      setFileName('Aucun fichier choisi');
    }
  };

  const handleJsonChange = (e) => {
    setJsonData(e.target.value);
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setResponseMsg(null);
    setIsLoading(true);

    if (!file) {
      setResponseMsg({ message: 'Veuillez sélectionner un fichier.', type: 'error' });
      setIsLoading(false);
      return;
    }

    const formData = new FormData();
    formData.append('excelFile', file);
    formData.append('jsonData', jsonData);

    try {
      const response = await axios.post('/api/upload/', formData);
      console.log('Réponse du serveur:', response.data);
      setResponseMsg({ message: JSON.stringify(response.data, null, 2), type: 'success' });
    } catch (error) {
      console.error('Erreur lors de l\'envoi:', error);
      let errorText = error.message;
      if (error.response && error.response.data) {
        errorText = JSON.stringify(error.response.data, null, 2);
      }
      setResponseMsg({ message: errorText, type: 'error' });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-2xl">

        <div className="bg-white rounded-lg shadow-xl p-6 md:p-8">
          <h1 className="text-2xl md:text-3xl font-bold text-gray-800 text-center mb-6">
            Démo de Déploiement React + Django
          </h1>

          <form onSubmit={handleSubmit} className="space-y-6">

            {/* --- Section JSON --- */}
            <div>
              <label htmlFor="jsonData" className="block text-sm font-medium text-gray-700 mb-1">
                1. Données JSON à envoyer
              </label>
              <textarea
                id="jsonData"
                value={jsonData}
                onChange={handleJsonChange}
                rows="6"
                className="w-full p-3 border border-gray-300 rounded-md shadow-sm focus:ring-indigo-500 focus:border-indigo-500 font-mono text-sm"
              />
            </div>

            {/* --- Section Fichier --- */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                2. Fichier (Excel, CSV, etc.)
              </label>
              <div className="mt-1 flex justify-center px-6 pt-5 pb-6 border-2 border-gray-300 border-dashed rounded-md">
                <div className="space-y-1 text-center">
                  <FileIcon />
                  <div className="flex text-sm text-gray-600">
                    <label
                      htmlFor="file-upload"
                      className="relative cursor-pointer bg-white rounded-md font-medium text-indigo-600 hover:text-indigo-500 focus-within:outline-none focus-within:ring-2 focus-within:ring-offset-2 focus-within:ring-indigo-500"
                    >
                      <span>Sélectionner un fichier</span>
                      <input id="file-upload" name="file-upload" type="file" className="sr-only" onChange={handleFileChange} />
                    </label>
                    <p className="pl-1">ou glissez-déposez</p>
                  </div>
                  <p className="text-xs text-gray-500">{fileName}</p>
                </div>
              </div>
            </div>

            {/* --- Bouton d'envoi --- */}
            <div>
              <button
                type="submit"
                disabled={isLoading}
                className={`w-full flex justify-center py-3 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white transition-colors duration-150 ${
                  isLoading
                    ? 'bg-indigo-400 cursor-not-allowed'
                    : 'bg-indigo-600 hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500'
                }`}
              >
                {isLoading ? (
                  <>
                    <SpinnerIcon />
                    Envoi en cours...
                  </>
                ) : (
                  'Envoyer au Backend'
                )}
              </button>
            </div>
          </form>

          {/* --- Section Réponse --- */}
          {responseMsg && (
            <div className="mt-6">
              <h3 className="text-lg font-medium text-gray-900 mb-2">Réponse du Serveur :</h3>
              <Alert message={responseMsg.message} type={responseMsg.type} />
            </div>
          )}

        </div>
      </div>
    </div>
  );
}

export default App;
