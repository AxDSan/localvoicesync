import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ui/theme/app_theme.dart';
import '../../features/recording/record_page.dart';
import '../../features/history/history_page.dart';
import '../../features/settings/settings_page.dart';
import '../widgets/app_clickable.dart';
import '../widgets/interim_results_window.dart';

final navigationProvider = StateProvider<int>((ref) => 0);

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgLight,
      body: Stack(
        children: [
          Row(
            children: [
              // Sidebar
              Container(
                width: 200,
                decoration: const BoxDecoration(
                  color: AppTheme.bgLightSecondary,
                  border: Border(
                    right: BorderSide(
                      color: AppTheme.borderLight,
                      width: 1,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    Expanded(
                      child: _SidebarNavigation(
                        currentIndex: currentIndex,
                        onTap: (index) {
                          ref.read(navigationProvider.notifier).state = index;
                        },
                      ),
                    ),
                    _SidebarFooter(),
                  ],
                ),
              ),
              // Main Content
              Expanded(
                child: IndexedStack(
                  index: currentIndex,
                  children: const [
                    RecordPage(),
                    HistoryPage(),
                    SettingsPage(),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SidebarNavigation extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const _SidebarNavigation({
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SidebarItem(
          icon: Icons.mic_rounded,
          label: 'Record',
          isActive: currentIndex == 0,
          onTap: () => onTap(0),
        ),
        _SidebarItem(
          icon: Icons.history_rounded,
          label: 'History',
          isActive: currentIndex == 1,
          onTap: () => onTap(1),
        ),
        _SidebarItem(
          icon: Icons.settings_rounded,
          label: 'Settings',
          isActive: currentIndex == 2,
          onTap: () => onTap(2),
        ),
      ],
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.skyBlue.withOpacity(0.1)
                : (_isHovered ? Colors.black.withOpacity(0.02) : Colors.transparent),
            border: Border(
              right: BorderSide(
                color: widget.isActive
                    ? AppTheme.skyBlue
                    : Colors.transparent,
                width: 4,
              ),
            ),
          ),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  color: widget.isActive
                      ? AppTheme.skyBlue
                      : (_isHovered ? AppTheme.textDark : AppTheme.textGray),
                  size: 24,
                ),
                const SizedBox(width: 16),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? AppTheme.skyBlue
                        : (_isHovered ? AppTheme.textDark : AppTheme.textGray),
                    fontWeight: widget.isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppTheme.borderLight,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _FooterLink(
            label: 'Official Website',
            url: 'https://github.com/AxDSan/localvoicesync',
          ),
          _FooterLink(
            label: 'Support',
            url: 'https://github.com/AxDSan/localvoicesync/issues',
          ),
          _FooterLink(
            label: 'Source Code',
            url: 'https://github.com/AxDSan/localvoicesync',
          ),
          const SizedBox(height: 12),
          Text(
            'Version: v1.0.0-Alpha',
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Developed with ♥️ by Abdias J.',
            style: const TextStyle(
              color: AppTheme.textDim,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final String label;
  final String url;

  const _FooterLink({
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return AppClickable(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text(
          label,
          style: const TextStyle(
            color: AppTheme.textDim,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
