from django.urls import path
from . import views

urlpatterns = [
    # POST /api/upload/
    path('upload/', views.UploadView.as_view(), name='upload_view'),
]
