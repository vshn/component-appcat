package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"

	appcatv1 "github.com/vshn/component-appcat/apis/v1"
)

// Remove some fields that are removed by Crossplane anyway.
// Some properties need to be added and removed by Crossplane (https://doc.crds.dev/github.com/crossplane/crossplane/apiextensions.crossplane.io/CompositeResourceDefinition/v1@v1.10.0)
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[].schema.openAPIV3Schema.properties; del(.metadata), del(.kind), del(.apiVersion))"
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .referenceable=true, del(.storage), del(.subresources))"

// Workaround to make nested defaulting work.
// kubebuilder is unable to set a {} default
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.default={})"
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.maintenance.default={})"
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.service.default={})"
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.size.default={})"
//go:generate yq -i e ../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.network.default={})"

// Patch the XRD with this generated CRD scheme
//go:generate yq -i e ../../../packages/composite/dbaas/exoscale/kafka.yml --expression ".parameters.appcat.composites.\"xexoscalekafkas.exoscale.appcat.vshn.io\".spec.versions=load(\"../../generated/exoscale.appcat.vshn.io_exoscalekafkas.yaml\").spec.versions"

// +kubebuilder:object:root=true
// +kubebuilder:printcolumn:name="Plan",type="string",JSONPath=".spec.parameters.size.plan"
// +kubebuilder:printcolumn:name="Zone",type="string",JSONPath=".spec.parameters.service.zone"
// +kubebuilder:printcolumn:name="Version",type="string",JSONPath=".status.version"

// ExoscaleKafka is the API for creating Kafka instances on Exoscale.
type ExoscaleKafka struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// Spec defines the desired state of a ExoscaleKafka.
	Spec ExoscaleKafkaSpec `json:"spec,omitempty"`
	// Status reflects the observed state of a ExoscaleKafka.
	Status ExoscaleKafkaStatus `json:"status,omitempty"`
}

type ExoscaleKafkaSpec struct {
	// Parameters are the configurable fields of a ExoscaleKafka.
	Parameters ExoscaleKafkaParameters `json:"parameters,omitempty"`
}

type ExoscaleKafkaParameters struct {

	// Service contains Exoscale Kafka DBaaS specific properties
	Service ExoscaleKafkaServiceSpec `json:"service,omitempty"`

	// Maintenance contains settings to control the maintenance of an instance.
	Maintenance ExoscaleDBaaSMaintenanceScheduleSpec `json:"maintenance,omitempty"`

	// Size contains settings to control the sizing of a service.
	Size ExoscaleKafkaDBaaSSizeSpec `json:"size,omitempty"`

	// Network contains any network related settings.
	Network ExoscaleDBaaSNetworkSpec `json:"network,omitempty"`
}

type ExoscaleKafkaDBaaSSizeSpec struct {
	// +kubebuilder:default="startup-2"

	// Plan is the name of the resource plan that defines the compute resources.
	Plan string `json:"plan,omitempty"`
}

type ExoscaleKafkaServiceSpec struct {
	ExoscaleDBaaSServiceSpec `json:",inline"`
	// KafkaSettings contains additional Kafka settings.
	KafkaSettings runtime.RawExtension `json:"kafkaSettings,omitempty"`

	// +kubebuilder:validation:Enum="3.2"
	// +kubebuilder:default="3.2"

	// Version contains the minor version for Kafka.
	// Currently only "3.2" is supported. Leave it empty to always get the latest supported version.
	Version string `json:"version,omitempty"`
}

type ExoscaleKafkaStatus struct {
	// KafkaConditions contains the status conditions of the backing object.
	KafkaConditions []appcatv1.Condition `json:"kafkaConditions,omitempty"`

	// The actual observed Kafka version.
	Version string `json:"version,omitempty"`
}
