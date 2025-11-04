from django.contrib import admin
from django.urls import path, include # Ajoutez 'include'
from django.conf import settings # Ajout
from django.conf.urls.static import static # Ajout

urlpatterns = [
    path('admin/', admin.site.urls),
    # Toute URL commençant par 'api/' sera gérée par notre app 'api'
    path('', include('api.urls')),
]

# Ajout pour servir les fichiers media en DÉVELOPPEMENT
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)