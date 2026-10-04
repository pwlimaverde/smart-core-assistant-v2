use flutter_rust_bridge::frb;
pub use velopack::{VelopackAsset, UpdateInfo};

#[frb(mirror(UpdateInfo))]
pub struct _UpdateInfo {
    /// The available version that we are updating to.
    pub TargetFullRelease: VelopackAsset,
    /// The base release that this update is based on. This is only available if the update is a delta update.
    pub BaseRelease: Option<VelopackAsset>,
    /// The list of delta updates that can be applied to the base version to get to the target version.
    pub DeltasToTarget: Vec<VelopackAsset>,
    /// True if the update is a version downgrade or lateral move (such as when switching channels to the same version number).
    /// In this case, only full updates are allowed, and any local packages on disk newer than the downloaded version will be
    /// deleted.
    pub IsDowngrade: bool,
}

#[frb(mirror(VelopackAsset))]
pub struct _VelopackAsset {
    /// The name or Id of the package containing this release.
    pub PackageId: String,
    /// The version of this release.
    pub Version: String,
    /// The type of asset (eg. "Full" or "Delta").
    pub Type: String,
    /// The filename of the update package containing this release.
    pub FileName: String,
    /// The SHA1 checksum of the update package containing this release.
    pub SHA1: String,
    /// The SHA256 checksum of the update package containing this release.
    pub SHA256: String,
    /// The size in bytes of the update package containing this release.
    pub Size: u64,
    /// The release notes in markdown format, as passed to Velopack when packaging the release. This may be an empty string.
    pub NotesMarkdown: String,
    /// The release notes in HTML format, transformed from Markdown when packaging the release. This may be an empty string.
    pub NotesHtml: String,
}

