#!/bin/bash

# URL que será acessada
URL="http://movie.ks1.cacttus.us/host"

# Número de repetições
NUM_REPS=800

# Loop para executar o comando curl 100 vezes
for i in $(seq 1 $NUM_REPS); do
    echo "Executando $i de $NUM_REPS..."
    curl -s -v  $URL
done

