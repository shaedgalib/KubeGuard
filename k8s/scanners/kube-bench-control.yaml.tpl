# kube-bench on the control-plane node (P2-U1). Rendered by infra/scans/run.sh, which fills in
# @KUBE_BENCH@ and @BENCHMARK@ from infra/versions.env. Read-only: host paths are mounted read-only
# and only paths that exist on the nodes are mounted, so nothing is created on the host.
# The API token is not mounted: the scanner reads files and processes and never calls the API.
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-control
  namespace: scanners
  labels:
    app.kubernetes.io/name: kube-bench
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kube-bench
    spec:
      restartPolicy: Never
      hostPID: true
      automountServiceAccountToken: false
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: node-role.kubernetes.io/control-plane
                    operator: Exists
      tolerations:
        - key: node-role.kubernetes.io/control-plane
          operator: Exists
          effect: NoSchedule
      containers:
        - name: kube-bench
          image: docker.io/aquasec/kube-bench:v@KUBE_BENCH@
          command: ["kube-bench", "run", "--benchmark", "@BENCHMARK@", "--targets", "master,etcd,controlplane,policies,node", "--json"]
          volumeMounts:
            - { name: etc-kubernetes, mountPath: /etc/kubernetes, readOnly: true }
            - { name: var-lib-etcd, mountPath: /var/lib/etcd, readOnly: true }
            - { name: var-lib-kubelet, mountPath: /var/lib/kubelet, readOnly: true }
            - { name: etc-systemd, mountPath: /etc/systemd, readOnly: true }
            - { name: lib-systemd, mountPath: /lib/systemd, readOnly: true }
            - { name: etc-cni-netd, mountPath: /etc/cni/net.d, readOnly: true }
            - { name: opt-cni-bin, mountPath: /opt/cni/bin, readOnly: true }
            - { name: etc-passwd, mountPath: /etc/passwd, readOnly: true }
            - { name: etc-group, mountPath: /etc/group, readOnly: true }
      volumes:
        - { name: etc-kubernetes, hostPath: { path: /etc/kubernetes, type: Directory } }
        - { name: var-lib-etcd, hostPath: { path: /var/lib/etcd, type: Directory } }
        - { name: var-lib-kubelet, hostPath: { path: /var/lib/kubelet, type: Directory } }
        - { name: etc-systemd, hostPath: { path: /etc/systemd, type: Directory } }
        - { name: lib-systemd, hostPath: { path: /lib/systemd, type: Directory } }
        - { name: etc-cni-netd, hostPath: { path: /etc/cni/net.d, type: Directory } }
        - { name: opt-cni-bin, hostPath: { path: /opt/cni/bin, type: Directory } }
        - { name: etc-passwd, hostPath: { path: /etc/passwd, type: File } }
        - { name: etc-group, hostPath: { path: /etc/group, type: File } }
