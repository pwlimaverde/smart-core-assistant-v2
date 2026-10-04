use std::sync::mpsc;
use std::sync::OnceLock;

use anyhow::{bail, Result};
use flutter_rust_bridge::frb;
use velopack::{
    sources, Error, UpdateCheck, UpdateInfo, UpdateManager, UpdateOptions, VelopackApp,
};

use crate::frb_generated::StreamSink;

struct VelopackConfig {
    url: String,
    /// Overrides the channel that updates are fetched from. When `None`, the
    /// channel the app was installed from is used.
    channel: Option<String>,
    /// Must be `true` to migrate to a version lower than the current one. This is
    /// required when switching to a channel whose latest version is older than
    /// the installed version.
    allow_downgrade: bool,
}

static VELOPACK_CONFIG: OnceLock<VelopackConfig> = OnceLock::new();

#[frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
    VelopackApp::build().run();
}

pub fn init_velopack(url: String, channel: Option<String>, allow_downgrade: bool) -> Result<()> {
    let config = VelopackConfig {
        url,
        channel,
        allow_downgrade,
    };

    if let Err(config) = VELOPACK_CONFIG.set(config) {
        if VELOPACK_CONFIG.get().map(|c| &c.url) == Some(&config.url) {
            return Ok(());
        }

        bail!("Velopack is already initialized with a different URL");
    }

    Ok(())
}

/// Builds an `UpdateManager` for the configured update source.
///
/// When `channel` is `Some`, it overrides the channel set at initialization for
/// this call only; when `None`, the channel from `initializeVelopack` (or the
/// install channel) is used.
///
/// When `allow_downgrade` is `Some`, it overrides the downgrade policy set at
/// initialization for this call only; when `None`, the value from
/// `initializeVelopack` is used. This is needed when switching to a channel
/// whose latest version is older than the installed version.
fn get_update_manager(
    channel: Option<String>,
    allow_downgrade: Option<bool>,
) -> Result<UpdateManager, Error> {
    let config = VELOPACK_CONFIG.get().ok_or(Error::Other(
        "Velopack not initialized. Call initializeVelopack() first.".into(),
    ))?;
    let source = sources::HttpSource::new(&config.url);
    let options = UpdateOptions {
        AllowVersionDowngrade: allow_downgrade.unwrap_or(config.allow_downgrade),
        ExplicitChannel: channel.or_else(|| config.channel.clone()),
        ..Default::default()
    };
    UpdateManager::new(source, Some(options), None)
}

pub fn is_update_available(channel: Option<String>, allow_downgrade: Option<bool>) -> Result<bool> {
    let um = get_update_manager(channel, allow_downgrade)?;
    let update_check = um.check_for_updates()?;
    Ok(matches!(update_check, UpdateCheck::UpdateAvailable(..)))
}

pub fn get_latest_update_info(
    channel: Option<String>,
    allow_downgrade: Option<bool>,
) -> Result<Option<UpdateInfo>> {
    let um = get_update_manager(channel, allow_downgrade)?;
    let update_check = um.check_for_updates()?;
    return match update_check {
        UpdateCheck::UpdateAvailable(updates) => Ok(Some(*updates)),
        _ => Ok(None),
    };
}

pub fn current_version() -> Result<String> {
    let um = get_update_manager(None, None)?;
    Ok(um.get_current_version_as_string())
}

pub fn check_and_download_updates_with_progress(
    progress_sink: StreamSink<i16>,
    channel: Option<String>,
    allow_downgrade: Option<bool>,
) -> Result<Option<UpdateInfo>> {
    let um = get_update_manager(channel, allow_downgrade)?;
    if let UpdateCheck::UpdateAvailable(updates) = um.check_for_updates()? {
        // Create a channel for progress messages
        let (sx, rx) = mpsc::channel();

        um.download_updates(&updates, Some(sx))?;

        std::thread::spawn(move || {
            while let Ok(progress) = rx.recv() {
                let _ = progress_sink.add(progress);
            }
        });

        Ok(Some(*updates))
    } else {
        Ok(None)
    }
}

fn check_and_download_updates(
    channel: Option<String>,
    allow_downgrade: Option<bool>,
) -> Result<Option<UpdateInfo>> {
    let um = get_update_manager(channel, allow_downgrade)?;
    if let UpdateCheck::UpdateAvailable(updates) = um.check_for_updates()? {
        um.download_updates(&updates, None)?;
        Ok(Some(*updates))
    } else {
        Ok(None)
    }
}

pub fn update_and_restart(channel: Option<String>, allow_downgrade: Option<bool>) -> Result<()> {
    if let Some(updates) = check_and_download_updates(channel.clone(), allow_downgrade)? {
        let um = get_update_manager(channel, allow_downgrade)?;
        um.apply_updates_and_restart(&updates)?;
    }
    Ok(())
}

pub fn update_and_exit(channel: Option<String>, allow_downgrade: Option<bool>) -> Result<()> {
    if let Some(updates) = check_and_download_updates(channel.clone(), allow_downgrade)? {
        let um = get_update_manager(channel, allow_downgrade)?;
        um.apply_updates_and_exit(&updates)?;
    }
    Ok(())
}

pub fn wait_exit_then_update(
    silent: bool,
    restart: bool,
    channel: Option<String>,
    allow_downgrade: Option<bool>,
) -> Result<()> {
    if let Some(updates) = check_and_download_updates(channel.clone(), allow_downgrade)? {
        let um = get_update_manager(channel, allow_downgrade)?;
        um.wait_exit_then_apply_updates(&updates, silent, restart, [""])?;
    }
    Ok(())
}
