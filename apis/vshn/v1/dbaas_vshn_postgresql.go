package v1

import (
	v1 "github.com/vshn/component-appcat/apis/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
)

// Workaround to make nested defaulting work.
// kubebuilder is unable to set a {} default
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.default={})"
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.size.default={})"
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.service.default={})"
//go:generate yq -i e ../../generated/vshn.appcat.vshn.io_vshnpostgresqls.yaml --expression "with(.spec.versions[]; .schema.openAPIV3Schema.properties.spec.properties.parameters.properties.backup.default={})"

// +kubebuilder:object:root=true

// VSHNPostgreSQL is the API for creating Postgresql clusters.
type VSHNPostgreSQL struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	// Spec defines the desired state of a VSHNPostgreSQL.
	Spec VSHNPostgreSQLSpec `json:"spec"`

	// Status reflects the observed state of a VSHNPostgreSQL.
	Status VSHNPostgreSQLStatus `json:"status,omitempty"`
}

// VSHNPostgreSQLSpec defines the desired state of a VSHNPostgreSQL.
type VSHNPostgreSQLSpec struct {
	// Parameters are the configurable fields of a VSHNPostgreSQL.
	Parameters VSHNPostgreSQLParameters `json:"parameters,omitempty"`
}

// VSHNPostgreSQLParameters are the configurable fields of a VSHNPostgreSQL.
type VSHNPostgreSQLParameters struct {
	// Service contains PostgreSQL DBaaS specific properties
	Service VSHNPostgreSQLServiceSpec `json:"service,omitempty"`

	// Maintenance contains settings to control the maintenance of an instance.
	Maintenance VSHNDBaaSMaintenanceScheduleSpec `json:"maintenance,omitempty"`

	// Size contains settings to control the sizing of a service.
	Size VSHNDBaaSSizeSpec `json:"size,omitempty"`

	// Scheduling contains settings to control the scheduling of an instance.
	Scheduling VSHNDBaaSSchedulingSpec `json:"scheduling,omitempty"`

	// Network contains any network related settings.
	Network VSHNDBaaSNetworkSpec `json:"network,omitempty"`

	// Backup contains settings to control the backups of an instance.
	Backup VSHNPostgreSQLBackup `json:"backup,omitempty"`
}

// VSHNPostgreSQLServiceSpec contains PostgreSQL DBaaS specific properties
type VSHNPostgreSQLServiceSpec struct {
	// +kubebuilder:validation:Enum="12";"13";"14";"15"
	// +kubebuilder:default="15"

	// MajorVersion contains supported version of PostgreSQL.
	// Multiple versions are supported. The latest version "15" is the default version.
	MajorVersion string `json:"majorVersion,omitempty"`

	// PGSettings contains additional PostgreSQL settings.
	PostgreSQLSettings runtime.RawExtension `json:"pgSettings,omitempty"`
}

// VSHNDBaaSSchedulingSpec contains settings to control the scheduling of an instance.
type VSHNDBaaSSchedulingSpec struct {
	// NodeSelector is a selector which must match a node’s labels for the pod to be scheduled on that node
	NodeSelector string `json:"nodeSelector,omitempty"`
}

// VSHNDBaaSMaintenanceScheduleSpec contains settings to control the maintenance of an instance.
type VSHNDBaaSMaintenanceScheduleSpec struct {
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

// VSHNDBaaSSizeSpec contains settings to control the sizing of a service.
type VSHNDBaaSSizeSpec struct {
	// +kubebuilder:default="600m"

	// CPU defines the amount of Kubernetes CPUs for an instance.
	CPU string `json:"cpu,omitempty"`

	// +kubebuilder:default="3500Mi"

	// Memory defines the amount of memory in units of bytes for an instance.
	Memory string `json:"memory,omitempty"`

	// +kubebuilder:default="5Gi"

	// Disk defines the amount of disk space for an instance.
	Disk string `json:"disk,omitempty"`
}

// VSHNDBaaSNetworkSpec contains any network related settings.
type VSHNDBaaSNetworkSpec struct {
	// +kubebuilder:default={"0.0.0.0/0"}

	// IPFilter is a list of allowed IPv4 CIDR ranges that can access the service.
	// If no IP Filter is set, you may not be able to reach the service.
	// A value of `0.0.0.0/0` will open the service to all addresses on the public internet.
	IPFilter []string `json:"ipFilter,omitempty"`
}

type VSHNPostgreSQLBackup struct {
	// +kubebuilder:validation:Pattern=^(\*|([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])|\*\/([0-9]|1[0-9]|2[0-9]|3[0-9]|4[0-9]|5[0-9])) (\*|([0-9]|1[0-9]|2[0-3])|\*\/([0-9]|1[0-9]|2[0-3])) (\*|([1-9]|1[0-9]|2[0-9]|3[0-1])|\*\/([1-9]|1[0-9]|2[0-9]|3[0-1])) (\*|([1-9]|1[0-2])|\*\/([1-9]|1[0-2])) (\*|([0-6])|\*\/([0-6]))$
	// +kubebuilder:default="0 22 * * *"
	Schedule string `json:"schedule,omitempty"`

	// +kubebuilder:validation:Pattern="^[1-9][0-9]*$"
	// +kubebuilder:default=6
	// +kubebuilder:validation:XIntOrString
	Retention int `json:"retention,omitempty"`
}

// VSHNPostgreSQLStatus reflects the observed state of a VSHNPostgreSQL.
type VSHNPostgreSQLStatus struct {
	// PostgreSQLConditions contains the status conditions of the backing object.
	PostgreSQLConditions []v1.Condition `json:"postgresqlConditions,omitempty"`
	NamespaceDebug       []v1.Condition `json:"namespaceDebug,omitempty"`
	ProfileDebug         []v1.Condition `json:"profileDebug,omitempty"`
	PGConfigDebug        []v1.Condition `json:"pgconfigDebug,omitempty"`
	PGClusterDebug       []v1.Condition `json:"pgclusterDebug,omitempty"`
	SecretsDebug         []v1.Condition `json:"secretDebug,omitempty"`
	S3BucketDebug        []v1.Condition `json:"s3BucketDebug,omitempty"`
	S3BackupConfigDebug  []v1.Condition `json:"s3BackupConfigDebug,omitempty"`
	NetworkPolicyDebug   []v1.Condition `json:"networkPolicyDebug,omitempty"`
	LocalCADebug         []v1.Condition `json:"localCADebug,omitempty"`
	CertificateDebug     []v1.Condition `json:"certificateDebug,omitempty"`
}
