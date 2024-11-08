#!/bin/bash

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nginx-1
  name: nginx-1
spec:
  containers:
  - image: nginx
    name: nginx
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  labels:
    run: nginx-1
  name: nginx-1
  namespace: default
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: nginx-1
  type: ClusterIP
---
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: nginx-2
  name: nginx-2
spec:
  containers:
  - image: nginx
    name: nginx
    resources: {}
  dnsPolicy: ClusterFirst
  restartPolicy: Always
---
apiVersion: v1
kind: Service
metadata:
  labels:
    run: nginx-2
  name: nginx-2
  namespace: default
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    run: nginx-2
  type: ClusterIP
---
EOF

export n1_status=$(kubectl get pod nginx-1 -o=jsonpath='{.status.phase}')
export n2_status=$(kubectl get pod nginx-2 -o=jsonpath='{.status.phase}')

while [[ "$n1_status" != "Running" && "$n2_status" != "Running" ]]; do

  export n1_status=$(kubectl get pod nginx-1 -o=jsonpath='{.status.phase}') 
  export n2_status=$(kubectl get pod nginx-2 -o=jsonpath='{.status.phase}')
  sleep 3
done

echo "testing connectivity"

echo "nginx-1 curling nginx-2"
kubectl exec nginx-1 -- curl -m2 -s -I nginx-2 | grep HTTP

echo "nginx-2 curling nginx-1"
kubectl exec nginx-2 -- curl -m2 -s -I nginx-1 | grep HTTP

echo "applying default-deny-ingress network policy"

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF

echo "testing connectivity, after default-deny-ingress is applied"

echo "nginx-1 curling nginx-2"
kubectl exec nginx-1 -- curl -m2 -s -I nginx-2 | grep HTTP

echo "nginx-2 curling nginx-1"
kubectl exec nginx-2 -- curl -m2 -s -I nginx-1 | grep HTTP

echo "applying allow-nginx2-to-nginx1 network policy"

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx2-to-nginx1
  namespace: default
spec:
  podSelector:
    matchLabels:
      run: nginx-1
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          run: nginx-2
    ports:
    - protocol: TCP
      port: 80
EOF

echo "testing connectivity, after allow-nginx2-to-nginx1 is applied"

echo "nginx-1 curling nginx-2"
kubectl exec nginx-1 -- curl -m2 -s -I nginx-2 | grep HTTP

echo "nginx-2 curling nginx-1"
kubectl exec nginx-2 -- curl -m2 -s -I nginx-1 | grep HTTP

echo "cleaning up"
kubectl delete pod nginx-1 nginx-2
kubectl delete svc nginx-1 nginx-2
kubectl delete networkpolicy default-deny-ingress allow-nginx2-to-nginx1