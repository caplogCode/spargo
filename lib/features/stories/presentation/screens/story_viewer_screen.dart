import 'package:flutter/material.dart' hide Text;
import 'package:spargo/shared/widgets/auto_translate_text.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_tokens.dart';
import '../../../../core/utils/web_image_proxy.dart';
import '../../../../domain/models/story_models.dart';
import '../../../../routing/app_routes.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../../shared/widgets/animated_cta_button.dart';
import '../../../../shared/widgets/cover_action_button.dart';
import '../../../../theme/app_colors.dart';

class StoryViewerScreen extends ConsumerStatefulWidget {
  const StoryViewerScreen({
    super.key,
    required this.storyId,
    this.initialItemIndex = 0,
  });

  final String storyId;
  final int initialItemIndex;

  @override
  ConsumerState<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends ConsumerState<StoryViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _next();
      }
    });
  late int _itemIndex = widget.initialItemIndex;
  int _storyIndex = 0;
  bool _isForward = true;
  final Set<String> _trackedStoryIds = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _play();
    });
  }

  List<Story> _storySequence(List<Story> availableStories) {
    final groupedStories = <String, List<Story>>{};
    final orderedBusinessIds = <String>[];

    void addStory(Story story) {
      final bucket = groupedStories.putIfAbsent(story.businessId, () {
        orderedBusinessIds.add(story.businessId);
        return <Story>[];
      });
      if (!bucket.any((entry) => entry.id == story.id)) {
        bucket.add(story);
      }
    }

    for (final story in availableStories) {
      addStory(story);
    }

    Story? initialStoryMatch;
    for (final story in availableStories) {
      if (story.id == widget.storyId) {
        initialStoryMatch = story;
        break;
      }
    }
    final Story initialStory =
        initialStoryMatch ?? ref.read(storyByIdProvider(widget.storyId));
    addStory(initialStory);

    final startBusinessIndex = orderedBusinessIds.indexOf(
      initialStory.businessId,
    );
    final orderedSequenceIds = <String>[
      ...orderedBusinessIds.skip(
        startBusinessIndex < 0 ? 0 : startBusinessIndex,
      ),
      if (startBusinessIndex > 0)
        ...orderedBusinessIds.take(startBusinessIndex),
    ];

    final orderedStories = <Story>[];
    for (final businessId in orderedSequenceIds) {
      final businessStories = groupedStories[businessId]!;
      if (businessId == initialStory.businessId) {
        final startIndex = businessStories.indexWhere(
          (story) => story.id == initialStory.id,
        );
        if (startIndex >= 0) {
          orderedStories.addAll(businessStories.skip(startIndex));
          orderedStories.addAll(businessStories.take(startIndex));
          continue;
        }
      }
      orderedStories.addAll(businessStories);
    }

    return orderedStories;
  }

  List<Story> _businessStoryGroup(List<Story> storySequence, Story story) {
    return storySequence
        .where((entry) => entry.businessId == story.businessId)
        .toList(growable: false);
  }

  int _storyItemProgressCount(List<Story> businessStories) {
    var count = 0;
    for (final story in businessStories) {
      count += story.items.isEmpty ? 1 : story.items.length;
    }
    return count == 0 ? 1 : count;
  }

  int _storyItemProgressIndex({
    required List<Story> businessStories,
    required Story currentStory,
    required int currentItemIndex,
  }) {
    var offset = 0;
    for (final story in businessStories) {
      if (story.id == currentStory.id) {
        final itemCount = story.items.isEmpty ? 1 : story.items.length;
        return offset + currentItemIndex.clamp(0, itemCount - 1).toInt();
      }
      offset += story.items.isEmpty ? 1 : story.items.length;
    }
    return currentItemIndex;
  }

  Future<void> _markCurrentStorySeenAndTrack(Story story) async {
    ref.read(storySeenProvider.notifier).markSeen(story.id);
    if (_trackedStoryIds.contains(story.id)) {
      return;
    }
    _trackedStoryIds.add(story.id);
    try {
      await ref.read(repositoryProvider).trackStoryView(story);
    } catch (_) {
      // Story playback should never break because of analytics.
    }
  }

  void _play() {
    final storySequence = _storySequence(ref.read(storiesProvider));
    if (storySequence.isEmpty) {
      return;
    }
    if (_storyIndex >= storySequence.length) {
      _storyIndex = 0;
    }
    final story = storySequence[_storyIndex];
    if (story.items.isEmpty) {
      _next();
      return;
    }
    if (_itemIndex >= story.items.length) {
      _itemIndex = 0;
    }
    _markCurrentStorySeenAndTrack(story);
    _controller.duration = story.items[_itemIndex].duration;
    _controller.forward(from: 0);
  }

  void _next() {
    final storySequence = _storySequence(ref.read(storiesProvider));
    if (storySequence.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final safeStoryIndex = _storyIndex >= storySequence.length
        ? storySequence.length - 1
        : _storyIndex;
    final story = storySequence[safeStoryIndex];
    if (story.items.isEmpty && _storyIndex < storySequence.length - 1) {
      setState(() {
        _isForward = true;
        _storyIndex += 1;
        _itemIndex = 0;
      });
      _play();
      return;
    }
    if (_itemIndex < story.items.length - 1) {
      setState(() {
        _isForward = true;
        _itemIndex += 1;
      });
      _play();
    } else if (_storyIndex < storySequence.length - 1) {
      setState(() {
        _isForward = true;
        _storyIndex += 1;
        _itemIndex = 0;
      });
      _play();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _previous() {
    final storySequence = _storySequence(ref.read(storiesProvider));
    if (storySequence.isEmpty) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    if (_itemIndex > 0) {
      setState(() {
        _isForward = false;
        _itemIndex -= 1;
      });
      _play();
      return;
    }
    if (_storyIndex == 0) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    final previousStory = storySequence[_storyIndex - 1];
    setState(() {
      _isForward = false;
      _storyIndex -= 1;
      _itemIndex = previousStory.items.isEmpty
          ? 0
          : previousStory.items.length - 1;
    });
    _play();
  }

  bool _canGoPrevious(List<Story> storySequence) {
    return _itemIndex > 0 || _storyIndex > 0;
  }

  String _nextLabel(List<Story> storySequence, Story story) {
    final lastStory = _storyIndex >= storySequence.length - 1;
    final lastItem = _itemIndex >= story.items.length - 1;
    return lastStory && lastItem ? 'Schließen' : 'Weiter';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storySequence = _storySequence(ref.watch(storiesProvider));
    final safeStoryIndex = _storyIndex >= storySequence.length
        ? storySequence.length - 1
        : _storyIndex;
    final story = storySequence[safeStoryIndex];
    if (story.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Align(
                  alignment: Alignment.topRight,
                  child: CoverActionButton(
                    onTap: () => Navigator.of(context).pop(),
                    icon: Icons.close_rounded,
                  ),
                ),
                const Spacer(),
                Text(
                  story.businessName.isEmpty ? 'Story' : story.businessName,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Diese Story hat gerade keine Inhalte.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.88),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      );
    }
    final safeItemIndex = _itemIndex >= story.items.length
        ? story.items.length - 1
        : _itemIndex;
    final item = story.items[safeItemIndex];
    final colors = item.palette.isEmpty
        ? <Color>[const Color(0xFF2B101A), const Color(0xFF5B1D31)]
        : item.palette.map(Color.new).toList();
    final imageUrl = item.imageUrl.trim();
    final business = ref.watch(businessByIdProvider(story.businessId));
    final businessImageUrl = business.imageUrl.trim();
    final logoUrl = webSafeImageUrl(
      businessImageUrl.isNotEmpty ? businessImageUrl : imageUrl,
    );
    final trimmedBusinessName = story.businessName.trim();
    final businessInitial = trimmedBusinessName.isEmpty
        ? '▶'
        : trimmedBusinessName[0].toUpperCase();
    final accentStart = colors.isNotEmpty
        ? colors.first
        : const Color(0xFFDB2149);
    final accentEnd = colors.length > 1 ? colors[1] : const Color(0xFFF07B94);
    final safeImageUrl = imageUrl.isEmpty ? null : webSafeImageUrl(imageUrl);
    final businessStoryGroup = _businessStoryGroup(storySequence, story);
    final progressItemCount = _storyItemProgressCount(businessStoryGroup);
    final progressItemIndex = _storyItemProgressIndex(
      businessStories: businessStoryGroup,
      currentStory: story,
      currentItemIndex: _itemIndex,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9FC),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return GestureDetector(
            onLongPressStart: (_) => _controller.stop(),
            onLongPressEnd: (_) => _controller.forward(),
            onVerticalDragUpdate: (details) {
              if (details.primaryDelta != null && details.primaryDelta! > 14) {
                Navigator.of(context).pop();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _StoryViewerBackdrop(accent: accentStart),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _previous,
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _next,
                      ),
                    ),
                  ],
                ),
                Positioned.fill(
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.md,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: Column(
                        children: <Widget>[
                          _StoryProgressStrip(
                            itemCount: progressItemCount,
                            itemIndex: progressItemIndex,
                            progress: _controller.value,
                            activeColor: accentStart,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: <Widget>[
                              _StoryAvatar(
                                logoUrl: logoUrl,
                                initial: businessInitial,
                                start: accentStart,
                                end: accentEnd,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      story.businessName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: AppColors.ink,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    Text(
                                      story.timeLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF7B7280),
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              _StoryCloseButton(
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            ],
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: AppDurations.medium,
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                final offsetAnimation =
                                    Tween<Offset>(
                                      begin: Offset(
                                        _isForward ? 0.08 : -0.08,
                                        0,
                                      ),
                                      end: Offset.zero,
                                    ).animate(
                                      CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                      ),
                                    );
                                return FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: offsetAnimation,
                                    child: child,
                                  ),
                                );
                              },
                              child: KeyedSubtree(
                                key: ValueKey<String>('${story.id}:${item.id}'),
                                child: _StoryContentCard(
                                  item: item,
                                  imageUrl: safeImageUrl,
                                  accent: accentStart,
                                  accentEnd: accentEnd,
                                ),
                              ),
                            ),
                          ),
                          if (item.dealId != null) ...<Widget>[
                            const SizedBox(height: AppSpacing.sm),
                            AnimatedCtaButton(
                              label: item.ctaLabel,
                              expanded: true,
                              onPressed: () =>
                                  Navigator.of(context).pushReplacementNamed(
                                    AppRoutes.dealDetail,
                                    arguments: DealRouteArgs(item.dealId!),
                                  ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Row(
                            children: <Widget>[
                              Expanded(
                                child: _StoryNavButton(
                                  label: 'Zurück',
                                  icon: Icons.arrow_back_rounded,
                                  enabled: _canGoPrevious(storySequence),
                                  onTap: _previous,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: _StoryNavButton(
                                  label: _nextLabel(storySequence, story),
                                  icon: Icons.arrow_forward_rounded,
                                  enabled: true,
                                  onTap: _next,
                                  primary: true,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StoryNavButton extends StatelessWidget {
  const _StoryNavButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : AppColors.ink;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: AppDurations.fast,
        opacity: enabled ? 1 : 0.42,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: primary ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary ? AppColors.primary : const Color(0xFFEDE5EC),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: (primary ? AppColors.primary : Colors.black).withValues(
                  alpha: primary ? 0.18 : 0.06,
                ),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: foreground, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryViewerBackdrop extends StatelessWidget {
  const _StoryViewerBackdrop({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Color(0xFFFFF8FB),
                Color(0xFFF7F9FF),
                Color(0xFFFFF7FA),
              ],
            ),
          ),
        ),
        Positioned(
          right: -88,
          top: 70,
          child: _StoryGlowBlob(
            size: 250,
            color: accent.withValues(alpha: 0.18),
          ),
        ),
        Positioned(
          left: -100,
          bottom: -64,
          child: _StoryGlowBlob(
            size: 270,
            color: const Color(0xFFA9D7FF).withValues(alpha: 0.18),
          ),
        ),
      ],
    );
  }
}

class _StoryGlowBlob extends StatelessWidget {
  const _StoryGlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _StoryProgressStrip extends StatelessWidget {
  const _StoryProgressStrip({
    required this.itemCount,
    required this.itemIndex,
    required this.progress,
    required this.activeColor,
  });

  final int itemCount;
  final int itemIndex;
  final double progress;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List<Widget>.generate(itemCount, (index) {
        final value = index < itemIndex
            ? 1.0
            : index == itemIndex
            ? progress
            : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                minHeight: 3.5,
                value: value,
                backgroundColor: const Color(0xFFE8E3EA),
                valueColor: AlwaysStoppedAnimation<Color>(activeColor),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({
    required this.logoUrl,
    required this.initial,
    required this.start,
    required this.end,
  });

  final String? logoUrl;
  final String initial;
  final Color start;
  final Color end;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: <Color>[start, end]),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: start.withValues(alpha: 0.22),
            blurRadius: 18,
            spreadRadius: -6,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: <Color>[start, end]),
                ),
              ),
              if (logoUrl != null)
                Image.network(
                  logoUrl!,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                  errorBuilder: (context, error, stackTrace) {
                    return const SizedBox.shrink();
                  },
                ),
              if (logoUrl == null)
                Center(
                  child: Text(
                    initial,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryCloseButton extends StatelessWidget {
  const _StoryCloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.92),
          border: Border.all(color: const Color(0xFFEDE5EC)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFF706672).withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(Icons.close_rounded, color: AppColors.ink, size: 22),
      ),
    );
  }
}

class _StoryContentCard extends StatelessWidget {
  const _StoryContentCard({
    required this.item,
    required this.imageUrl,
    required this.accent,
    required this.accentEnd,
  });

  final StoryItem item;
  final String? imageUrl;
  final Color accent;
  final Color accentEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 430),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withValues(alpha: 0.10),
              blurRadius: 34,
              spreadRadius: -14,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: AspectRatio(
                aspectRatio: 1.02,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            accent.withValues(alpha: 0.16),
                            accentEnd.withValues(alpha: 0.08),
                            Colors.white,
                          ],
                        ),
                      ),
                    ),
                    if (imageUrl != null)
                      Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox.shrink();
                        },
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0),
                            Colors.black.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                    ),
                    if (imageUrl == null)
                      Center(
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          size: 74,
                          color: accent.withValues(alpha: 0.86),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              item.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w900,
                height: 1.04,
              ),
            ),
            if (item.subtitle.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                item.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: const Color(0xFF514A55),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            if (item.body.trim().isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.sm),
              Text(
                item.body,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF6E6570),
                  height: 1.35,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
