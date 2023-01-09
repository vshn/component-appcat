package v1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// Remove some fields that are removed by Crossplane anyway.
// Some properties need to be added and removed by Crossplane (https://doc.crds.dev/github.com/crossplane/crossplane/apiextensions.crossplane.io/CompositeResourceDefinition/v1@v1.10.0)
//go:generate yq -i e ../generated/appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[].schema.openAPIV3Schema.properties; del(.metadata), del(.kind), del(.apiVersion))"
//go:generate yq -i e ../generated/appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .referenceable=true, del(.storage), del(.subresources))"

// Workaround to make nested defaulting work.
// kubebuilder is unable to set a {} default
//go:generate yq -i e ../generated/appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.default={})"
//go:generate yq -i e ../generated/appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.size.default={})"
//go:generate yq -i e ../generated/appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.service.default={})"

// Patch the XRD with this generated CRD scheme
//go:generate yq -i e ".parameters.appcat.composites.\"xvshnpostgresqls.appcat.vshn.io\".spec.versions=load(\"../generated/appcat.vshn.io_vshnpostgresqls.yaml\").spec.versions" ../../packages/composite/vshn/postgresql.yml

// +kubebuilder:object:root=true

// VSHNPostgreSQL is the API for creating Postgresql clusters.
type VSHNPostgreSQL struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VSHNPostgreSQLSpec   `json:"spec"`
	Status VSHNPostgreSQLStatus `json:"status,omitempty"`
}

// VSHNPostgreSQLSpec defines the desired state of a VSHNPostgreSQL.
type VSHNPostgreSQLSpec struct {
	Parameters VSHNPostgreSQLParameters `json:"parameters,omitempty"`
}

// VSHNPostgreSQLParameters are the configurable fields of a VSHNPostgreSQL.
type VSHNPostgreSQLParameters struct {
	// Service contains  PostgreSQL DBaaS specific properties
	Service PostgreSQLServiceSpec `json:"service,omitempty"`

	// Maintenance contains settings to control the maintenance of an instance.
	Maintenance DBaaSMaintenanceScheduleSpec `json:"maintenance,omitempty"`

	// Size contains settings to control the sizing of a service.
	Size DBaaSSizeSpec `json:"size,omitempty"`

	// Network contains any network related settings.
	Network DBaaSNetworkSpec `json:"network,omitempty"`

	// Backup contains settings to control the backups of an instance.
	Backup DBaaSBackupSpec `json:"backup,omitempty"`
}
type PostgreSQLServiceSpec struct {
	// +kubebuilder:validation:Enum="12";"13";"14";"15"
	// +kubebuilder:default="15"

	// majorVersion contains supported version of PostgreSQL.
	// "15" is default version
	MajorVersion string `json:"majorVersion,omitempty"`

	// PGSettings contains additional PostgreSQL settings.
	PostgreSQLSettings runtime.RawExtension `json:"pgSettings,omitempty"`
}

// VSHNPostgreSQLStatus reflects the observed state of a VSHNPostgreSQL.
type VSHNPostgreSQLStatus struct {
	// AccessUserConditions contains a copy of the claim's underlying user account conditions.
	AccessUserConditions []Condition `json:"accessUserConditions,omitempty"`
	// BucketConditions contains a copy of the claim's underlying bucket conditions.
	BucketConditions []Condition `json:"bucketConditions,omitempty"`
}

type DBaaSMaintenanceScheduleSpec struct {
	// +kubebuilder:validation:Enum=monday;tuesday;wednesday;thursday;friday;saturday;sunday;never
	// +kubebuilder:default="tuesday"

	// DayOfWeek specifies at which weekday the maintenance is held place.
	// Allowed values are [monday, tuesday, wednesday, thursday, friday, saturday, sunday, never]
	DayOfWeek string `json:"dayOfWeek,omitempty"`

	// +kubebuilder:validation:Pattern="^([0-1]?[0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])$"
	// +kubebuilder:default="22:30:00"

	// TimeOfDay for installing updates in UTC.
	// Format: "hh:mm:ss".
	TimeOfDay string `json:"timeOfDay,omitempty"`
}

type DBaaSSizeSpec struct {
	// +kubebuilder:default="500m"
	Cpu string `json:"cpu,omitempty"`
	// +kubebuilder:default="128Mi"
	Memory string `json:"memory,omitempty"`
	// +kubebuilder:default="5Gi"
	Disk string `json:"disk,omitempty"`
}

type DBaaSNetworkSpec struct {
	// +kubebuilder:default={"0.0.0.0/0"}

	// IPFilter is a list of allowed IPv4 CIDR ranges that can access the service.
	// If no IP Filter is set, you may not be able to reach the service.
	// A value of `0.0.0.0/0` will open the service to all addresses on the public internet.
	IPFilter []string `json:"ipFilter,omitempty"`
}

type DBaaSBackupSpec struct {
	// +kubebuilder:validation:Pattern="^([0-1]?[0-9]|2[0-3]):([0-5][0-9]):([0-5][0-9])$"
	// +kubebuilder:default="21:30:00"

	// TimeOfDay for doing daily backups, in UTC.
	// Format: "hh:mm:ss".
	TimeOfDay string `json:"timeOfDay,omitempty"`
}
type ExoscalePostgreSQLStatus struct {
	// PostgreSQLConditions contains the status conditions of the backing object.
	PostgreSQLConditions []Condition `json:"postgresqlConditions,omitempty"`
}
