import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';

/// Reusable error display widget shown by StreamBuilder/FutureBuilder
/// when data loading fails. Shows the error message and, in debug or
/// profile mode, the stack trace. Provides a Retry button that calls
/// [onRetry].
class ErrorDisplayWidget extends StatelessWidget {
  final Object? error;
  final StackTrace? stackTrace;
  final VoidCallback onRetry;
  final String? fallbackMessage;

  const ErrorDisplayWidget({
    super.key,
    required this.error,
    this.stackTrace,
    required this.onRetry,
    this.fallbackMessage,
  });

  @override
  Widget build(BuildContext context) {
    final message = error?.toString() ?? fallbackMessage ?? 'An error occurred';
    final showStackTrace = !kReleaseMode && stackTrace != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            if (showStackTrace) ...[
              const SizedBox(height: 12),
              ExpansionTile(
                title: const Text(
                  'Show stack trace',
                  style: TextStyle(fontSize: 12),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      stackTrace.toString(),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A FutureBuilder that shows a loading spinner, an error display with
/// retry support, or the child builder when data is available.
class ResilientFutureBuilder<T> extends StatelessWidget {
  final Future<T> Function() futureBuilder;
  final Widget Function(BuildContext, AsyncSnapshot<T>) builder;
  final T? initialData;

  const ResilientFutureBuilder({
    super.key,
    required this.futureBuilder,
    required this.builder,
    this.initialData,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: futureBuilder(),
      initialData: initialData,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorDisplayWidget(
            error: snapshot.error,
            stackTrace: snapshot.stackTrace,
            onRetry: () {
              // Trigger a rebuild which re-calls futureBuilder
              (context as Element).markNeedsBuild();
            },
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData &&
            initialData == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return builder(context, snapshot);
      },
    );
  }
}
