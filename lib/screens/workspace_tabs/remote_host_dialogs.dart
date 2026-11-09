import 'dart:async';

import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../models/models.dart';
import '../../services/services.dart';
import 'remote_host_labels.dart';

/// The public setup guide for remote hosts.
final remoteHostsSetupGuide = Uri.parse(
  'https://devmil.de/processlama/remote-hosts.html',
);

Future<void> openRemoteHostsSetupGuide() async {
  await launchUrl(remoteHostsSetupGuide);
}

/// The workflows of the remote host service, asking and reporting through
/// dialogs and toasts on [context].
RemoteHostWorkflows remoteHostWorkflows(BuildContext context) =>
    RemoteHostWorkflows(
      remoteHosts: context.read<RemoteHostService>(),
      port: DialogRemoteHostInteractionPort(context),
    );

/// The name a remote host is shown with; the alias never appears in
/// announcements.
String remoteHostName(BuildContext context, String profileId) =>
    context
        .read<RemoteHostService>()
        .hosts
        .value
        .profile(profileId)
        ?.displayName ??
    '';

/// Marks the part of the window that outlives tab switches. Remote host
/// workflows ask and report from its context: the widget that starts one
/// may belong to a tab's explorer, which is rebuilt when the workflow opens
/// or switches tabs.
class WorkspaceDialogAnchor extends StatefulWidget {
  const WorkspaceDialogAnchor({super.key, required this.child});

  final Widget child;

  /// The anchor's context, or [context] without an anchor.
  static BuildContext contextOf(BuildContext context) =>
      context.findAncestorStateOfType<_WorkspaceDialogAnchorState>()?.context ??
      context;

  @override
  State<WorkspaceDialogAnchor> createState() => _WorkspaceDialogAnchorState();
}

class _WorkspaceDialogAnchorState extends State<WorkspaceDialogAnchor> {
  @override
  Widget build(BuildContext context) => widget.child;
}

/// Asks in Meridian dialogs and reports in toasts, while the window is
/// open.
final class DialogRemoteHostInteractionPort
    implements RemoteHostInteractionPort {
  DialogRemoteHostInteractionPort(BuildContext context)
    : context = WorkspaceDialogAnchor.contextOf(context);

  final BuildContext context;

  @override
  bool get isActive => context.mounted;

  @override
  Future<RemoteInstallChoice> confirmInstall(
    RemoteInstallRequest request,
  ) async {
    if (!context.mounted) {
      return RemoteInstallChoice.cancel;
    }
    final choice = await showMeridianDialog<RemoteInstallChoice>(
      context: context,
      builder: (_) => RemoteHelperInstallDialog(request: request),
    );
    return choice ?? RemoteInstallChoice.cancel;
  }

  @override
  Future<bool> confirmHelperRemoval(RemoteHostProfile profile) async {
    if (!context.mounted) {
      return false;
    }
    final l10n = context.l10n;
    return showMeridianConfirm(
      context,
      title: l10n.remoteHelperRemoveTitle(profile.displayName),
      description: l10n.remoteHelperRemoveBody,
      confirmLabel: l10n.remoteHelperRemoveAction,
      cancelLabel: l10n.remoteHostCancel,
      destructive: true,
    );
  }

  @override
  void report(RemoteHostReport report) {
    if (!context.mounted) {
      return;
    }
    final l10n = context.l10n;
    final host = remoteHostName(context, report.profileId);
    final reason = switch (report.failure) {
      null => '',
      final code => l10n.remoteFailure(code),
    };
    final (message, tone) = switch (report.kind) {
      RemoteHostReportKind.helperInstalled => (
        l10n.remoteHelperInstalled(host),
        MeridianToastTone.success,
      ),
      RemoteHostReportKind.installFailed => (
        l10n.remoteHelperInstallFailed(host, reason),
        MeridianToastTone.error,
      ),
      RemoteHostReportKind.helperUnavailable => (
        l10n.remoteHelperInstallUnavailable(host),
        MeridianToastTone.error,
      ),
      RemoteHostReportKind.connectFailed => (
        l10n.remoteHostConnectFailed(host, reason),
        MeridianToastTone.error,
      ),
      RemoteHostReportKind.helperRemoved => (
        l10n.remoteHelperRemoved(host),
        MeridianToastTone.success,
      ),
      RemoteHostReportKind.removalFailed => (
        l10n.remoteHelperRemoveFailed(host),
        MeridianToastTone.error,
      ),
    };
    showMeridianToast(context, message: message.trim(), tone: tone);
  }
}

/// Asks before copying the helper to a host (§4.4): the host, path,
/// version, size and checksum prefix.
class RemoteHelperInstallDialog extends StatelessWidget {
  const RemoteHelperInstallDialog({super.key, required this.request});

  final RemoteInstallRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final host = request.profile.displayName;
    final update = request.isUpdate;
    void choose(RemoteInstallChoice choice) =>
        Navigator.of(context).pop(choice);
    return MeridianDialog(
      title: update
          ? l10n.remoteHelperUpdateTitle(host)
          : l10n.remoteHelperInstallTitle(host),
      description: l10n.remoteHelperInstallBody,
      width: MeridianLayout.dialogMaxWidth,
      onSubmit: () => choose(RemoteInstallChoice.install),
      content: MeridianPropertyList(
        properties: [
          MeridianProperty(
            label: l10n.remoteHelperInstallPath,
            value: request.installPath,
          ),
          MeridianProperty(
            label: l10n.remoteHelperInstallVersion,
            value:
                '${remotePlatform(request.target)} · '
                '${request.artifact.buildId.substring(0, 12)}',
          ),
          MeridianProperty(
            label: l10n.remoteHelperInstallSize,
            value: formatRemoteBytes(request.artifact.size),
          ),
          MeridianProperty(
            label: l10n.remoteHelperInstallChecksum,
            value: request.sha256Prefix,
          ),
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.remoteHostCancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => choose(RemoteInstallChoice.cancel),
        ),
        MeridianButton(
          label: update
              ? l10n.remoteHelperUpdateAlways
              : l10n.remoteHelperInstallAlways,
          onPressed: () => choose(RemoteInstallChoice.installAlways),
        ),
        MeridianButton(
          label: update
              ? l10n.remoteHelperUpdateAction
              : l10n.remoteHelperInstallAction,
          variant: MeridianButtonVariant.primary,
          autofocus: true,
          onPressed: () => choose(RemoteInstallChoice.install),
        ),
      ],
    );
  }
}

/// `512 KB`-style sizes in binary units.
String formatRemoteBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 10 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Opens the profile editor; returns the saved profile, or null.
Future<RemoteHostProfile?> showRemoteHostEditor(
  BuildContext context, {
  RemoteHostProfile? profile,
}) => showMeridianDialog<RemoteHostProfile>(
  context: context,
  builder: (_) => RemoteHostEditorDialog(
    service: context.read<RemoteHostService>(),
    profile: profile,
  ),
);

enum _StartupChoice { remember, always, never }

/// Adds or edits a remote host profile (§4.2).
class RemoteHostEditorDialog extends StatefulWidget {
  const RemoteHostEditorDialog({
    super.key,
    required this.service,
    this.profile,
  });

  final RemoteHostService service;

  /// The profile to edit; null adds one.
  final RemoteHostProfile? profile;

  @override
  State<RemoteHostEditorDialog> createState() => _RemoteHostEditorDialogState();
}

class _RemoteHostEditorDialogState extends State<RemoteHostEditorDialog> {
  late final _name = TextEditingController(
    text: widget.profile?.displayName ?? '',
  );
  late final _alias = TextEditingController(
    text: widget.profile?.sshAlias ?? '',
  );
  late bool _autoInstall = widget.profile?.autoInstallHelper ?? false;
  late bool _autoReconnect = widget.profile?.autoReconnect ?? true;
  late _StartupChoice _startup = switch (widget.profile?.openOnStartup) {
    null => _StartupChoice.remember,
    true => _StartupChoice.always,
    false => _StartupChoice.never,
  };
  late BackgroundRefreshMode? _refresh = widget.profile?.backgroundRefresh;
  bool _nameEdited = false;
  bool _showErrors = false;
  bool _saving = false;
  bool _testing = false;
  RemoteProbeResult? _probe;
  String? _saveError;
  int _probeSerial = 0;

  @override
  void initState() {
    super.initState();
    _nameEdited = widget.profile != null;
  }

  @override
  void dispose() {
    _name.dispose();
    _alias.dispose();
    super.dispose();
  }

  String get _aliasValue => _alias.text.trim();

  /// The display name defaults to the alias.
  String get _nameValue {
    final name = _name.text.trim();
    return name.isEmpty ? _aliasValue : name;
  }

  bool get _aliasValid => RemoteHostProfile.isValidAlias(_aliasValue);
  bool get _nameValid => RemoteHostProfile.isValidDisplayName(_nameValue);

  void _aliasChanged(String value) {
    setState(() {
      // A different host must be trusted again.
      _autoInstall = false;
      _probe = null;
      _probeSerial++;
      if (!_nameEdited) {
        _name.text = value.trim();
      }
    });
  }

  Future<void> _test() async {
    if (!_aliasValid) {
      setState(() => _showErrors = true);
      return;
    }
    final serial = ++_probeSerial;
    setState(() {
      _testing = true;
      _probe = null;
    });
    final result = await widget.service.testConnection(_aliasValue);
    if (!mounted || serial != _probeSerial) {
      return;
    }
    setState(() {
      _testing = false;
      _probe = result;
    });
  }

  Future<void> _save() async {
    if (!_aliasValid || !_nameValid) {
      setState(() => _showErrors = true);
      return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    final openOnStartup = switch (_startup) {
      _StartupChoice.remember => null,
      _StartupChoice.always => true,
      _StartupChoice.never => false,
    };
    final l10n = context.l10n;
    try {
      final existing = widget.profile;
      final RemoteHostProfile saved;
      if (existing == null) {
        saved = await widget.service.addProfile(
          RemoteHostProfileDraft(
            sshAlias: _aliasValue,
            displayName: _nameValue,
            autoInstallHelper: _autoInstall,
            autoReconnect: _autoReconnect,
            openOnStartup: openOnStartup,
            backgroundRefresh: _refresh,
          ),
        );
      } else {
        saved = existing.copyWith(
          displayName: _nameValue,
          sshAlias: _aliasValue,
          autoInstallHelper: _autoInstall,
          autoReconnect: _autoReconnect,
          openOnStartup: () => openOnStartup,
          backgroundRefresh: () => _refresh,
        );
        await widget.service.updateProfile(saved);
      }
      if (mounted) {
        Navigator.of(context).pop(saved);
      }
    } on RemoteHostProfileRejected catch (error) {
      setState(() {
        _saving = false;
        _saveError = error.reason == RemoteHostProfileRejection.tooManyProfiles
            ? l10n.remoteHostTooMany
            : l10n.remoteHostSaveFailed;
      });
    } on RemoteHostsSaveFailure {
      setState(() {
        _saving = false;
        _saveError = l10n.remoteHostSaveFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final probe = _probe;
    final defaultMode = widget.service.hosts.value.defaultBackgroundRefresh;
    return MeridianDialog(
      title: widget.profile == null
          ? l10n.remoteHostEditorAddTitle
          : l10n.remoteHostEditorEditTitle,
      width: MeridianLayout.dialogMaxWidth,
      scrollable: true,
      onSubmit: _saving ? null : _save,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MeridianTextField(
            key: const ValueKey('remote-host-alias'),
            controller: _alias,
            label: l10n.remoteHostAlias,
            autofocus: widget.profile == null,
            monospace: true,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: remoteHostAliasMaxLength,
            message: l10n.remoteHostAliasHelp,
            error: _showErrors && !_aliasValid
                ? l10n.remoteHostAliasInvalid
                : null,
            onChanged: _aliasChanged,
          ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianTextField(
            key: const ValueKey('remote-host-name'),
            controller: _name,
            label: l10n.remoteHostDisplayName,
            maxLength: remoteHostDisplayNameMaxLength,
            error: _showErrors && !_nameValid
                ? l10n.remoteHostDisplayNameInvalid
                : null,
            onChanged: (_) => setState(() => _nameEdited = true),
          ),
          const SizedBox(height: MeridianSpace.space4),
          MeridianSettingsGroup(
            children: [
              MeridianSettingsRow(
                label: l10n.remoteHostConnection,
                children: [
                  MeridianSwitch(
                    label: l10n.remoteHostAutoInstall,
                    value: _autoInstall,
                    onChanged: (value) => setState(() => _autoInstall = value),
                  ),
                  MeridianSwitch(
                    label: l10n.remoteHostAutoReconnect,
                    value: _autoReconnect,
                    onChanged: (value) =>
                        setState(() => _autoReconnect = value),
                  ),
                ],
              ),
              MeridianSettingsRow(
                label: l10n.remoteHostOpenOnStartup,
                children: [
                  MeridianSegmented<_StartupChoice>(
                    label: l10n.remoteHostOpenOnStartup,
                    value: _startup,
                    onChanged: (value) => setState(() => _startup = value),
                    segments: [
                      MeridianSegment(
                        value: _StartupChoice.remember,
                        label: l10n.remoteHostOpenOnStartupRemember,
                      ),
                      MeridianSegment(
                        value: _StartupChoice.always,
                        label: l10n.remoteHostOpenOnStartupAlways,
                      ),
                      MeridianSegment(
                        value: _StartupChoice.never,
                        label: l10n.remoteHostOpenOnStartupNever,
                      ),
                    ],
                  ),
                ],
              ),
              MeridianSettingsRow(
                label: l10n.remoteHostBackgroundRefresh,
                children: [
                  MeridianSelect<BackgroundRefreshMode?>(
                    label: l10n.remoteHostBackgroundRefresh,
                    value: _refresh,
                    values: const [null, ...BackgroundRefreshMode.values],
                    valueLabel: (mode) => mode == null
                        ? '${l10n.remoteHostBackgroundRefreshDefault} '
                              '(${l10n.remoteRefresh(defaultMode)})'
                        : l10n.remoteRefresh(mode),
                    onChanged: (mode) => setState(() => _refresh = mode),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: MeridianSpace.space4),
          Row(
            children: [
              MeridianButton(
                key: const ValueKey('remote-host-test'),
                label: l10n.remoteHostTestConnection,
                icon: MeridianIcons.circlePlay,
                loading: _testing,
                onPressed: _testing ? null : _test,
              ),
              const SizedBox(width: MeridianSpace.space4),
              Expanded(
                child: Text(
                  _testing
                      ? l10n.remoteHostProbeRunning
                      : probe == null
                      ? ''
                      : l10n.remoteProbe(probe),
                  key: const ValueKey('remote-host-probe-result'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.meridian.text.caption.copyWith(
                    color: probe?.outcome == RemoteProbeOutcome.ready
                        ? context.meridian.colors.success
                        : context.meridian.colors.inkMuted,
                  ),
                ),
              ),
              MeridianButton(
                label: l10n.remoteHostSetupGuide,
                icon: MeridianIcons.bookOpen,
                variant: MeridianButtonVariant.quiet,
                onPressed: () => unawaited(openRemoteHostsSetupGuide()),
              ),
            ],
          ),
          if (_saveError case final error?) ...[
            const SizedBox(height: MeridianSpace.space4),
            MeridianBanner(tone: MeridianBannerTone.error, message: error),
          ],
        ],
      ),
      actions: [
        MeridianButton(
          label: l10n.remoteHostCancel,
          variant: MeridianButtonVariant.quiet,
          onPressed: () => Navigator.of(context).pop(),
        ),
        MeridianButton(
          key: const ValueKey('remote-host-save'),
          label: l10n.remoteHostSave,
          variant: MeridianButtonVariant.primary,
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }
}
