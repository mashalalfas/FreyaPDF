import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// A custom [PageRouteBuilder] that uses a Lottie animation as a splash
/// overlay while the destination page loads.
class LottiePageRoute<T> extends PageRouteBuilder<T> {
  /// Path to the Lottie JSON asset.
  final String lottieAsset;

  LottiePageRoute({
    required WidgetBuilder builder,
    this.lottieAsset = 'assets/animations/document_open.json',
    super.transitionDuration = const Duration(milliseconds: 600),
    super.reverseTransitionDuration = const Duration(milliseconds: 400),
    super.settings,
    super.fullscreenDialog,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final pageFade = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
              ),
            );
            final pageSlide = Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
              ),
            );

            final lottieOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.0, 0.15, curve: Curves.easeIn),
              ),
            );
            final lottieFadeOut =
                Tween<double>(begin: 1.0, end: 0.0).animate(
              CurvedAnimation(
                parent: animation,
                curve: const Interval(0.5, 0.7, curve: Curves.easeOut),
              ),
            );

            return Stack(
              children: [
                SlideTransition(
                  position: pageSlide,
                  child: FadeTransition(
                    opacity: pageFade,
                    child: child,
                  ),
                ),
                FadeTransition(
                  opacity: lottieOpacity,
                  child: FadeTransition(
                    opacity: lottieFadeOut,
                    child: _LottieOverlay(asset: lottieAsset),
                  ),
                ),
              ],
            );
          },
        );
}

class _LottieOverlay extends StatefulWidget {
  final String asset;
  const _LottieOverlay({required this.asset});

  @override
  State<_LottieOverlay> createState() => _LottieOverlayState();
}

class _LottieOverlayState extends State<_LottieOverlay> {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: RepaintBoundary(
          child: Lottie.asset(
            widget.asset,
            width: 120,
            height: 120,
            repeat: false,
            animate: true,
            errorBuilder: (context, error, stackTrace) {
              return Icon(
                Icons.picture_as_pdf_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              );
            },
          ),
        ),
      ),
    );
  }
}
