package v1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// +kubebuilder:object:root=true
// +kubebuilder:printcolumn:name="Bucket Name",type="string",JSONPath=".spec.parameters.bucketName"
// +kubebuilder:printcolumn:name="Region",type="string",JSONPath=".spec.parameters.region"

const (
	// DeleteAll recursively deletes all objects in the object bucket and then removes it.
	DeleteAll DeletionPolicy = "DeleteAll"
	// DeleteIfEmpty only deletes the object bucket if it's empty.
	DeleteIfEmpty DeletionPolicy = "DeleteIfEmpty"
)

// DeletionPolicy determines how object buckets should be deleted.
type DeletionPolicy string

// ObjectBucket is the API for creating S3 buckets.
type ObjectBucket struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ObjectBucketSpec   `json:"spec"`
	Status ObjectBucketStatus `json:"status,omitempty"`
}

// ObjectBucketSpec defines the desired state of a ObjectBucket.
type ObjectBucketSpec struct {
	Parameters ObjectBucketParameters `json:"parameters,omitempty"`
}

// ObjectBucketParameters are the configurable fields of a ObjectBucket.
type ObjectBucketParameters struct {
	// +kubebuilder:validation:Required

	// BucketName is the name of the bucket to create.
	// Cannot be changed after bucket is created.
	// Name must be acceptable by the S3 protocol, which follows RFC 1123.
	// Be aware that S3 providers may require a unique name across the platform or region.
	BucketName string `json:"bucketName"`

	// +kubebuilder:validation:Required

	// Region is the name of the region where the bucket shall be created.
	// The region must be available in the S3 endpoint.
	Region string `json:"region"`

	// +kubebuilder:validation:Enum="DeleteAll";"DeleteIfEmpty";
	// +kubebuilder:default="DeleteAll"
	// DeletionPolicy determines how object buckets should be deleted.
	// `DeleteAll` recursively deletes all objects in the object bucket and then removes it.
	// `DeleteIfEmpty` only deletes the object bucket if it's empty.
	DeletionPolicy DeletionPolicy `json:"deletionPolicy,omitempty"`
}

// ObjectBucketStatus reflects the observed state of a ObjectBucket.
type ObjectBucketStatus struct {
	// AccessUserConditions contains a copy of the claim's underlying user account conditions.
	AccessUserConditions []Condition `json:"accessUserConditions,omitempty"`
	// BucketConditions contains a copy of the claim's underlying bucket conditions.
	BucketConditions []Condition `json:"bucketConditions,omitempty"`
}
