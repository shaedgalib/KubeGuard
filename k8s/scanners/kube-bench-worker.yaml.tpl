# kube-bench on the worker nodes (P2-U1): one pod per worker (anti-affinity), kubelet checks only.
# Rendered by infra/scans/run.sh, which fills in @KUBE_BENCH@, @BENCHMARK@ and @WORKERS@ (the number
# of workers in infra/libvirt/nodes.conf). Same read-only, no-API-token rules as the control Job.
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-bench-worker
  namespace: scanners
  labels:
    app.kubernetes.io/name: kube-bench
spec:
  backoffLimit: 0
  completions: @WORKERS@
  parallelism: @WORKERS@
  template:
    metadata:
      labels:
        app.kubernetes.io/name: kube-bench
        app.kubernetes.io/component: worker
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
                    operator: DoesNotExist
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            - topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app.kubernetes.io/name: kube-bench
                  app.kubernetes.io/component: worker
      containers:
        - name: kube-bench
          image: docker.io/aquasec/kube-bench:v@KUBE_BENCH@
          command: ["kube-bench", "run", "--benchmark", "@BENCHMARK@", "--targets", "node", "--json"]
          volumeMounts:
            - { name: etc-kubernetes, mountPath: /etc/kubernetes, readOnly: true }
            - { name: var-lib-kubelet, mountPath: /var/lib/kubelet, readOnly: true }
            - { name: etc-systemd, mountPath: /etc/systemd, readOnly: true }
            - { name: lib-systemd, mountPath: /lib/systemd, readOnly: true }
            - { name: etc-cni-netd, mountPath: /etc/cni/net.d, readOnly: true }
            - { name: opt-cni-bin, mountPath: /opt/cni/bin, readOnly: true }
            - { name: etc-passwd, mountPath: /etc/passwd, readOnly: true }
            - { name: etc-group, mountPath: /etc/group, readOnly: true }
      volumes:
        - { name: etc-kubernetes, hostPath: { path: /etc/kubernetes, type: Directory } }
        - { name: var-lib-kubelet, hostPath: { path: /var/lib/kubelet, type: Directory } }
        - { name: etc-systemd, hostPath: { path: /etc/systemd, type: Directory } }
        - { name: lib-systemd, hostPath: { path: /lib/systemd, type: Directory } }
        - { name: etc-cni-netd, hostPath: { path: /etc/cni/net.d, type: Directory } }
        - { name: opt-cni-bin, hostPath: { path: /opt/cni/bin, type: Directory } }
        - { name: etc-passwd, hostPath: { path: /etc/passwd, type: File } }
        - { name: etc-group, hostPath: { path: /etc/group, type: File } }
