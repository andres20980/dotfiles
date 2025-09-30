# Demo policies for basic Kubernetes governance
package kubernetes.demo

# Simple required labels policy
violation[{"msg": msg, "details": details}] {
    # Check if the resource is a Deployment or Service
    input.kind == "Deployment"
    
    # Check if required labels are missing
    required_labels := {"app", "version", "environment"}
    labels := input.metadata.labels
    
    # Find missing labels
    missing := required_labels - object.keys(labels)
    count(missing) > 0
    
    msg := sprintf("Missing required labels: %v", [missing])
    details := {
        "resource": sprintf("%s/%s", [input.kind, input.metadata.name]),
        "namespace": input.metadata.namespace,
        "missing_labels": missing
    }
}

# Warning for certain service types
warn[{"msg": msg, "details": details}] {
    input.kind == "Service"
    input.spec.type == "LoadBalancer"
    
    msg := "LoadBalancer services may incur cloud costs in production"
    details := {
        "resource": sprintf("%s/%s", [input.kind, input.metadata.name]),
        "service_type": input.spec.type
    }
}

# Allow decisions for compliant resources
allow {
    input.kind == "Deployment"
    required_labels := {"app", "version", "environment"}
    labels := input.metadata.labels
    missing := required_labels - object.keys(labels)
    count(missing) == 0
}

allow {
    input.kind == "Service"
    input.spec.type != "LoadBalancer"
}

# Simple resource limit checks
violation[{"msg": msg, "details": details}] {
    input.kind == "Deployment"
    container := input.spec.template.spec.containers[_]
    not container.resources.limits.memory
    
    msg := "Container must have memory limits set"
    details := {
        "container": container.name,
        "resource": sprintf("%s/%s", [input.kind, input.metadata.name])
    }
}