

Link:
https://kubernetes.github.io/ingress-nginx/deploy



helm upgrade --install ingress-nginx ingress-nginx \
  --repo https://kubernetes.github.io/ingress-nginx \
  --namespace ingress-nginx --create-namespace




helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

 helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --create-namespace -n monitoring 
