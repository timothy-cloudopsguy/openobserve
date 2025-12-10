import base64, json
import requests
from datetime import datetime, timezone
import argparse
import time
import uuid
import random

# Parse command line arguments
parser = argparse.ArgumentParser(description='Send multiple logs to OpenObserve')
parser.add_argument('--host', type=str, default='https://openobserve-ingester.example.com', help='OpenObserve host')
parser.add_argument('--org', type=str, default='default', help='OpenObserve organization')
parser.add_argument('--stream', type=str, default='quickstart1', help='OpenObserve stream')
parser.add_argument('--user', type=str, default='root@example.com', help='OpenObserve user')
parser.add_argument('--password', type=str, default='xyzabc123', help='OpenObserve password')

parser.add_argument('num_logs', type=int, help='Number of logs to send')
parser.add_argument('--delay', type=float, default=0.0,
                    help='Delay in seconds between log sends (default: 0.0)')
args = parser.parse_args()

# user = "admin@calanalytics.com"
user = args.user
# password = "oNJST18BnmzjyOQB"
password = args.password
bas64encoded_creds = base64.b64encode(bytes(user + ":" + password, "utf-8")).decode("utf-8")

headers = {"Content-type": "application/json", "Authorization": "Basic " + bas64encoded_creds}
# org = "default"
org = args.org
# stream = "quickstart1"
stream = args.stream
openobserve_host = args.host
openobserve_url = openobserve_host + "/api/" + org + "/" + stream + "/_json"

print(f"Sending {args.num_logs} logs to OpenObserve...")

for i in range(args.num_logs):
    # Generate fresh UTC timestamp for each log
    current_timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

    # Generate unique identifiers for each log
    unique_pod_id = str(uuid.uuid4())
    unique_docker_id = ''.join(random.choices('0123456789abcdef', k=64))
    unique_revision_hash = ''.join(random.choices('0123456789abcdef', k=16))
    pod_instance = random.randint(1, 5)  # Random pod instance 1-5

    data = [{
        "kubernetes.annotations.kubectl.kubernetes.io/default-container": "prometheus",
        "kubernetes.annotations.kubernetes.io/psp": "eks.privileged",
        "kubernetes.container_hash": "quay.io/prometheus/prometheus@sha256:4748e26f9369ee7270a7cd3fb9385c1adb441c05792ce2bce2f6dd622fd91d38",
        "kubernetes.container_image": "quay.io/prometheus/prometheus:v2.39.1",
        "kubernetes.container_name": "prometheus",
        "kubernetes.docker_id": unique_docker_id,
        "kubernetes.host": "ip-10-2-50-35.us-east-2.compute.internal",
        "kubernetes.labels.app.kubernetes.io/component": "prometheus",
        "kubernetes.labels.app.kubernetes.io/instance": "k8s",
        "kubernetes.labels.app.kubernetes.io/managed-by": "prometheus-operator",
        "kubernetes.labels.app.kubernetes.io/name": "prometheus",
        "kubernetes.labels.app.kubernetes.io/part-of": "kube-prometheus",
        "kubernetes.labels.app.kubernetes.io/version": "2.39.1",
        "kubernetes.labels.controller-revision-hash": f"prometheus-k8s-{unique_revision_hash}",
        "kubernetes.labels.operator.prometheus.io/name": "k8s",
        "kubernetes.labels.operator.prometheus.io/shard": "0",
        "kubernetes.labels.prometheus": "k8s",
        "kubernetes.labels.statefulset.kubernetes.io/pod-name": f"prometheus-k8s-{pod_instance}",
        "kubernetes.namespace_name": "monitoring",
        "kubernetes.pod_id": unique_pod_id,
        "kubernetes.pod_name": f"prometheus-k8s-{pod_instance}",
        "log": f"ts={current_timestamp} caller=klog.go:108 level=warn component=k8s_client_runtime func=Warningf msg=\"pkg/mod/k8s.io/client-go@v0.25.1/tools/cache/reflector.go:169: failed to list *v1.Pod: pods is forbidden: User \\\"system:serviceaccount:monitoring:prometheus-k8s\\\" cannot list resource \\\"pods\\\" in API group \\\"\\\" at the cluster scope\" log_id={i+1} unique_id={unique_pod_id[:8]}",
        "stream": "stderr"
    }]

    res = requests.post(openobserve_url, headers=headers, data=json.dumps(data))

    if res.status_code == 200:
        print(f"Log {i+1}/{args.num_logs} sent successfully")
    else:
        print(f"Log {i+1}/{args.num_logs} failed with status code: {res.status_code}")

    # Add delay between requests if specified
    if args.delay > 0 and i < args.num_logs - 1:
        time.sleep(args.delay)

print(f"Finished sending {args.num_logs} logs!")
