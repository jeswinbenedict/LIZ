import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/responsive/breakpoints.dart';
import '../../app/theme.dart';
import 'sign_in_view.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: context.canPop()
            ? IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: MaxWidth(
            maxWidth: 460,
            // A card on wider screens, so the form has an edge; on a phone the
            // screen is the card.
            child: context.isPhone
                ? _form(context)
                : DecoratedBox(
                    decoration: ShapeDecoration(
                      color: context.liz.surface,
                      shape: LizRadius.shape(
                        LizRadius.lg,
                        side: BorderSide(color: context.liz.hairline),
                      ),
                      shadows: LizShadows.raised(context.liz),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _form(context),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _form(BuildContext context) => SignInView(
    onSignedIn: () {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    },
  );
}
