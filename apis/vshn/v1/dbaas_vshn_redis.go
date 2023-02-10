package v1

import (
	v1 "github.com/vshn/component-appcat/apis/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Workaround to make nested defaulting work.
// kubebuilder is unable to set a {} default
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnredis.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.default={})"
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnredis.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.size.default={})"
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnredis.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.service.default={})"

// +kubebuilder:object:root=true

// VSHNRedis is the API for creating Redis clusters.
type VSHNRedis struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// Spec defines the desired state of a VSHNRedis.
	Spec VSHNRedisSpec `json:"spec"`
}

// VSHNRedisSpec defines the desired state of a VSHNRedis.
type VSHNRedisSpec struct {
	// Parameters are the configurable fields of a VSHNRedis.
	Parameters VSHNRedisParameters `json:"parameters,omitempty"`
}

// VSHNRedisParameters are the configurable fields of a VSHNRedis.
type VSHNRedisParameters struct {
	// Service contains Redis DBaaS specific properties
	Service VSHNRedisServiceSpec `json:"service,omitempty"`

	// Size contains settings to control the sizing of a service.
	Size VSHNRedisSizeSpec `json:"size,omitempty"`
}

// VSHNRedisServiceSpec contains Redis DBaaS specific properties
type VSHNRedisServiceSpec struct {
	// +kubebuilder:validation:Enum="6.2";"7.0"
	// +kubebuilder:default="7.0"

	// Version contains supported version of Redis.
	// Multiple versions are supported. The latest version "7.0" is the default version.
	Version string `json:"version,omitempty"`

	// RedisSettings contains additional Redis settings.
	RedisSettings string `json:"redisSettings,omitempty"`
}

// VSHNRedisSizeSpec contains settings to control the sizing of a service.
type VSHNRedisSizeSpec struct {
	// +kubebuilder:default="500m"

	// CPURequests defines the requests amount of Kubernetes CPUs for an instance.
	CPURequests string `json:"cpuRequests,omitempty"`

	// +kubebuilder:default="500m"

	// CPULimits defines the limits amount of Kubernetes CPUs for an instance.
	CPULimits string `json:"cpuLimits,omitempty"`

	// +kubebuilder:default="2048Mi"

	// MemoryRequests defines the requests amount of memory in units of bytes for an instance.
	MemoryRequests string `json:"memoryRequests,omitempty"`

	// +kubebuilder:default="2048Mi"

	// MemoryLimits defines the limits amount of memory in units of bytes for an instance.
	MemoryLimits string `json:"memoryLimits,omitempty"`

	// +kubebuilder:default="5Gi"

	// Disk defines the amount of disk space for an instance.
	Disk string `json:"disk,omitempty"`
}
