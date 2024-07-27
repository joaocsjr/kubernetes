

helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn/longhorn --name longhorn --namespace longhorn-system --version 1.4.1



kubectl create namespace longhorn-system
helm install longhorn longhorn/longhorn --namespace longhorn-system
