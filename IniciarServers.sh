#!/bin/bash

echo "🚀 Iniciando servidores PICADE..."

tmux new-session -d -s picade-back "docker exec -it PICADE_APP php artisan serve --host=0.0.0.0 --port=8000"

tmux new-session -d -s picade-front "docker exec -it PICADE_APP npm run dev"

echo "✅ Backend y frontend corriendo"
echo "Para verlos:"
echo "tmux attach -t picade-back"
echo "tmux attach -t picade-front"

echo "Servidores iniciados en segundo plano"