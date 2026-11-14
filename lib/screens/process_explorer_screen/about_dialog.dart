part of '../process_explorer_screen.dart';

extension _AboutDialog on _ProcessExplorerScreenState {
  Future<void> _showAbout(ProcessService processService) async {
    final l10n = context.l10n;
    final version = context.read<AppUpdateService>().loadInstalledVersion();
    processService.setModalOverlayOpen(true);
    try {
      await showMeridianDialog<void>(
        context: context,
        builder: (dialogContext) {
          final meridian = dialogContext.meridian;
          return MeridianDialog(
            title: l10n.aboutApp,
            scrollable: true,
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SvgPicture.asset(
                  'resources/brand/tile-mimameidr.svg',
                  width: ProcessLamaTheme.aboutTileSize,
                  height: ProcessLamaTheme.aboutTileSize,
                  excludeFromSemantics: true,
                ),
                const SizedBox(height: MeridianSpace.space4),
                Text(l10n.aboutProductName, style: meridian.text.bodyStrong),
                Text(l10n.makerLine, style: meridian.text.body),
                FutureBuilder<InstalledAppVersion>(
                  future: version,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return info == null
                        ? const SizedBox.shrink()
                        : Text(
                            l10n.aboutVersion(info.version, '${info.build}'),
                            style: meridian.text.caption,
                          );
                  },
                ),
                const SizedBox(height: MeridianSpace.space4),
                Text(l10n.lamaFamily, style: meridian.text.bodyStrong),
                Text(
                  'ProcessLama · GitLama · MailLama · ShotLama · NoteLama',
                  style: meridian.text.body,
                ),
              ],
            ),
            actions: [
              MeridianButton(
                key: const ValueKey('about-licenses'),
                label: l10n.aboutLicenses,
                variant: MeridianButtonVariant.secondary,
                onPressed: () async {
                  final info = await version.then<InstalledAppVersion?>(
                    (info) => info,
                    onError: (Object _) => null,
                  );
                  if (!dialogContext.mounted) return;
                  await showMeridianLicenses(
                    context: dialogContext,
                    applicationName: l10n.aboutProductName,
                    applicationVersion: info == null
                        ? null
                        : l10n.aboutVersion(info.version, '${info.build}'),
                    applicationIcon: SvgPicture.asset(
                      'resources/brand/tile-mimameidr.svg',
                      width: ProcessLamaTheme.licenseTileSize,
                      height: ProcessLamaTheme.licenseTileSize,
                      excludeFromSemantics: true,
                    ),
                  );
                },
              ),
              MeridianButton(
                label: l10n.closeAbout,
                autofocus: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        },
      );
    } finally {
      processService.setModalOverlayOpen(false);
    }
  }
}
